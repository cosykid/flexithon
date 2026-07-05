// Agentic email-discovery + draft-writing loop for venue outreach.
// Self-contained (own Tavily + page-fetch tools) so the function deploys
// without cross-function imports.

const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ?? "https://api.openai.com/v1")
  .replace(/\/$/, "");
const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
// Outreach needs no vision, so a faster text model can be substituted for
// the (slower) vision model classify-report uses.
const AI_MODEL = Deno.env.get("OUTREACH_AI_MODEL") ??
  Deno.env.get("AI_MODEL") ?? "gpt-4o-mini";
const TAVILY_API_KEY = Deno.env.get("TAVILY_API_KEY") ?? "";

// Free-tier edge functions get ~150s wall clock; leave headroom for the
// photo copies and DB writes around the loop.
const MAX_ITERATIONS = 6;
const DEADLINE_MS = 130_000;
const MAX_PAGE_CHARS = 8_000;

const SYSTEM_PROMPT = `You help wheelchair users advocate for accessibility fixes.
A location has accumulated multiple verified accessibility-barrier reports. Your job:
1. Identify who is responsible for the location. If a venue name is given, use it. If only GPS
   coordinates are given, call find_nearby_venues and match against the report descriptions; if you
   cannot confidently identify a single responsible venue/institution, submit email null — emailing
   the wrong business is far worse than no email.
2. Find the venue's public contact email address. Use web_search (e.g. "<venue> <address> contact email")
   and fetch_page on the venue's own website (contact/about pages are best). Prefer the venue's own
   domain over aggregator sites. You may only submit an email address that appears verbatim in a
   tool result during this conversation — NEVER guess, construct, or pattern-infer an address.
3. Call submit_outreach exactly once with the email (or null if none found after searching),
   the URL of the page where the email appears, and a draft email.
You have a strict time budget: use at most 2 web_search calls and 2 fetch_page calls, then submit.
The draft is written in first person on behalf of a community member who reported a barrier.
Tone: constructive, specific, respectful — the goal is a fix, not a complaint. Mention the number
of independent reports and the date range, name the barrier(s), and ask what the venue's plans are.
Do NOT include any placeholder like [Your Name]; sign off simply as "A community member" style is
also wrong — end with "Kind regards," and nothing after. Do not include photo links; they are
appended automatically. Keep the body under 1200 characters.`;

export interface OutreachInput {
  venueName: string | null; // null = untagged location, identify via GPS
  venueAddress: string | null;
  lat: number;
  lng: number;
  reportCount: number;
  dateRange: string;
  barrierSummary: string; // "stairs (3), narrow_entrance (2)"
  descriptions: string[]; // report descriptions, newest first
}

export interface OutreachResult {
  email: string | null;
  emailSourceUrl: string | null;
  subject: string;
  body: string;
  model: string;
}

const TOOLS = [
  {
    type: "function",
    function: {
      name: "web_search",
      description: "Search the web. Returns titles, URLs and content snippets.",
      parameters: {
        type: "object",
        properties: { query: { type: "string" } },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "fetch_page",
      description: "Fetch a web page and return its visible text (truncated).",
      parameters: {
        type: "object",
        properties: { url: { type: "string" } },
        required: ["url"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "find_nearby_venues",
      description: "List venues within ~50m of a GPS position (Google Places). Use when no venue is tagged.",
      parameters: {
        type: "object",
        properties: {
          lat: { type: "number" },
          lng: { type: "number" },
        },
        required: ["lat", "lng"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "submit_outreach",
      description: "Submit the found email (or null) and the draft outreach email. Call exactly once.",
      parameters: {
        type: "object",
        properties: {
          email: { type: ["string", "null"], description: "Contact email found in a tool result, or null" },
          email_source_url: { type: ["string", "null"], description: "URL of the page the email appears on" },
          subject: { type: "string" },
          body: { type: "string", description: "Plain-text email body, under 1200 characters" },
        },
        required: ["email", "email_source_url", "subject", "body"],
      },
    },
  },
];

export async function runOutreach(input: OutreachInput): Promise<OutreachResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEADLINE_MS);
  try {
    return await runLoop(input, controller.signal);
  } finally {
    clearTimeout(timer);
  }
}

async function runLoop(input: OutreachInput, signal: AbortSignal): Promise<OutreachResult> {
  // deno-lint-ignore no-explicit-any
  const messages: any[] = [
    { role: "system", content: SYSTEM_PROMPT },
    {
      role: "user",
      content:
        (input.venueName
          ? `Venue: ${input.venueName}${input.venueAddress ? `, ${input.venueAddress}` : ""}\n`
          : "Venue: not tagged — identify it from the GPS position first.\n") +
        `GPS: ${input.lat}, ${input.lng}\n` +
        `Verified reports: ${input.reportCount} (${input.dateRange})\n` +
        `Barriers reported: ${input.barrierSummary}\n` +
        `Report descriptions:\n${input.descriptions.map((d) => `- ${d}`).join("\n")}`,
    },
  ];

  // Everything tools returned this run; the only text an email may come from.
  let toolOutputs = "";

  for (let i = 0; i < MAX_ITERATIONS; i++) {
    const res = await fetch(`${AI_BASE_URL}/chat/completions`, {
      method: "POST",
      signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${AI_API_KEY}`,
      },
      body: JSON.stringify({
        model: AI_MODEL,
        messages,
        tools: TOOLS,
        tool_choice: "auto",
        temperature: 0,
      }),
    });
    if (!res.ok) {
      throw new Error(`AI endpoint error ${res.status}: ${(await res.text()).slice(0, 300)}`);
    }
    const data = await res.json();
    const msg = data.choices?.[0]?.message;
    if (!msg) throw new Error("AI endpoint returned no message");

    const toolCalls = msg.tool_calls ?? [];
    if (toolCalls.length === 0) {
      messages.push(msg, {
        role: "user",
        content: "You must call submit_outreach with your draft.",
      });
      continue;
    }

    messages.push(msg);
    for (const tc of toolCalls) {
      const name = tc.function?.name;
      let args: Record<string, unknown> = {};
      try {
        args = JSON.parse(tc.function?.arguments ?? "{}");
      } catch { /* empty args */ }

      if (name === "submit_outreach") {
        return normalize(args, toolOutputs);
      }

      let result: string;
      if (name === "web_search") {
        result = await webSearch(String(args.query ?? ""));
      } else if (name === "fetch_page") {
        result = await fetchPage(String(args.url ?? ""));
      } else if (name === "find_nearby_venues") {
        result = await findNearbyVenues(Number(args.lat), Number(args.lng));
      } else {
        result = JSON.stringify({ error: `unknown tool ${name}` });
      }
      toolOutputs += "\n" + result;
      messages.push({ role: "tool", tool_call_id: tc.id, content: result });
    }
  }
  throw new Error("outreach loop exceeded max iterations without submit_outreach");
}

function normalize(args: Record<string, unknown>, toolOutputs: string): OutreachResult {
  let email = typeof args.email === "string" ? args.email.trim() : null;
  let sourceUrl = typeof args.email_source_url === "string" ? args.email_source_url : null;

  // Hard anti-hallucination gate: the address must appear verbatim in a tool
  // result. A guessed email means users mail a stranger — worse than no email.
  if (email !== null) {
    const wellFormed = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
    const seen = toolOutputs.toLowerCase().includes(email.toLowerCase());
    if (!wellFormed || !seen) {
      email = null;
      sourceUrl = null;
    }
  }

  return {
    email,
    emailSourceUrl: email === null ? null : sourceUrl,
    subject: String(args.subject ?? "Accessibility barrier reports at your venue").slice(0, 150),
    body: String(args.body ?? "").slice(0, 1600),
    model: AI_MODEL,
  };
}

async function findNearbyVenues(lat: number, lng: number): Promise<string> {
  const key = Deno.env.get("GOOGLE_PLACES_KEY") ?? "";
  if (!key) return JSON.stringify({ error: "places lookup unavailable" });
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return JSON.stringify({ error: "invalid coordinates" });
  }
  const res = await fetch("https://places.googleapis.com/v1/places:searchNearby", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": key,
      "X-Goog-FieldMask":
        "places.displayName,places.formattedAddress,places.websiteUri,places.googleMapsUri",
    },
    body: JSON.stringify({
      maxResultCount: 8,
      locationRestriction: {
        circle: { center: { latitude: lat, longitude: lng }, radius: 50.0 },
      },
    }),
  });
  if (!res.ok) return JSON.stringify({ error: `places lookup failed: ${res.status}` });
  const data = await res.json();
  const venues = (data.places ?? []).map((p: Record<string, unknown>) => ({
    name: (p.displayName as Record<string, unknown>)?.text,
    address: p.formattedAddress,
    website: p.websiteUri,
    maps_url: p.googleMapsUri,
  }));
  return JSON.stringify({ venues });
}

async function webSearch(query: string): Promise<string> {
  if (!TAVILY_API_KEY) return JSON.stringify({ error: "web search unavailable" });
  const res = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${TAVILY_API_KEY}`,
    },
    body: JSON.stringify({
      api_key: TAVILY_API_KEY,
      query,
      max_results: 5,
      include_answer: false,
    }),
  });
  if (!res.ok) return JSON.stringify({ error: `search failed: ${res.status}` });
  const data = await res.json();
  const results = (data.results ?? []).map((r: Record<string, unknown>) => ({
    title: r.title,
    url: r.url,
    content: String(r.content ?? "").slice(0, 500),
  }));
  return JSON.stringify({ results });
}

async function fetchPage(url: string): Promise<string> {
  if (!/^https?:\/\//.test(url)) return JSON.stringify({ error: "invalid url" });
  try {
    const res = await fetch(url, {
      redirect: "follow",
      headers: { "User-Agent": "AccessMapBot/1.0 (accessibility outreach)" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return JSON.stringify({ error: `fetch failed: ${res.status}` });
    const html = await res.text();
    // Strip tags but keep mailto hrefs — contact pages often hide the address
    // in the href with a friendlier link text.
    const mailtos = [...html.matchAll(/mailto:([^"'?\s>]+)/gi)].map((m) => m[1]);
    const text = html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;|&amp;|&lt;|&gt;|&#\d+;/g, " ")
      .replace(/\s+/g, " ")
      .slice(0, MAX_PAGE_CHARS);
    return JSON.stringify({ url, mailto_links: mailtos, text });
  } catch (e) {
    return JSON.stringify({ error: `fetch failed: ${e}` });
  }
}
