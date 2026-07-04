// Server-side implementations of the tools exposed to the model.

const TAVILY_API_KEY = Deno.env.get("TAVILY_API_KEY") ?? "";
const GOOGLE_PLACES_KEY = Deno.env.get("GOOGLE_PLACES_KEY") ?? "";

export const toolDefinitions = [
  {
    type: "function",
    function: {
      name: "web_search",
      description:
        "Search the web for information about a venue's accessibility. Returns titles, URLs and content snippets.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_place_accessibility",
      description:
        "Look up a venue's wheelchair accessibility claim on Google Places by place_id. Returns the venue's own accessibility claim, or null if it claims nothing.",
      parameters: {
        type: "object",
        properties: {
          place_id: { type: "string", description: "Google Places place id" },
        },
        required: ["place_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "submit_verdict",
      description:
        "Submit your final factual verdict. Call exactly once, after any investigation. You report facts only; you do not decide the report's classification.",
      parameters: {
        type: "object",
        properties: {
          image_confirms_barrier: {
            type: ["boolean", "null"],
            description:
              "Does the photo clearly show the claimed accessibility barrier? null if no photo was provided.",
          },
          barrier_type: {
            type: ["string", "null"],
            enum: ["stairs", "no_ramp", "narrow_entrance", "broken_lift", "other", null],
          },
          venue_claims_accessible: {
            type: ["boolean", "null"],
            description:
              "Does the venue claim wheelchair accessibility online? null if no venue tagged or no claim found.",
          },
          web_corroboration_found: {
            type: "boolean",
            description: "Did web search corroborate the barrier claim?",
          },
          image_contradicts_report: {
            type: "boolean",
            description:
              "True only if the photo actively contradicts the description (e.g. shows a clearly accessible ramp when stairs are claimed) or is unrelated/spam.",
          },
          confidence: { type: "string", enum: ["low", "medium", "high"] },
          reasoning: { type: "string" },
        },
        required: [
          "web_corroboration_found",
          "image_contradicts_report",
          "confidence",
          "reasoning",
        ],
      },
    },
  },
];

export async function webSearch(query: string): Promise<string> {
  if (!TAVILY_API_KEY) return JSON.stringify({ error: "search unavailable" });
  const res = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Current Tavily auth; api_key in the body kept for older deployments.
      Authorization: `Bearer ${TAVILY_API_KEY}`,
    },
    body: JSON.stringify({
      api_key: TAVILY_API_KEY,
      query,
      max_results: 5,
    }),
  });
  if (!res.ok) return JSON.stringify({ error: `search failed: ${res.status}` });
  const data = await res.json();
  const results = (data.results ?? []).map(
    (r: { title: string; url: string; content: string }) => ({
      title: r.title,
      url: r.url,
      snippet: r.content?.slice(0, 500),
    }),
  );
  return JSON.stringify({ results });
}

// Returns the venue's accessibility claim deterministically. The caller keeps
// this raw value and trusts it over the model's echo in the verdict.
export async function getPlaceAccessibility(
  placeId: string,
): Promise<{ raw: string; claim: boolean | null }> {
  if (!GOOGLE_PLACES_KEY) {
    return { raw: JSON.stringify({ error: "places unavailable" }), claim: null };
  }
  const res = await fetch(
    `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
    {
      headers: {
        "X-Goog-Api-Key": GOOGLE_PLACES_KEY,
        // Field mask is mandatory; accessibilityOptions is the Pro SKU.
        "X-Goog-FieldMask": "accessibilityOptions,displayName",
      },
    },
  );
  if (!res.ok) {
    return { raw: JSON.stringify({ error: `places failed: ${res.status}` }), claim: null };
  }
  const data = await res.json();
  const entrance = data.accessibilityOptions?.wheelchairAccessibleEntrance;
  const claim = typeof entrance === "boolean" ? entrance : null;
  return {
    raw: JSON.stringify({
      venue: data.displayName?.text ?? null,
      wheelchair_accessible_entrance: claim,
      accessibility_options: data.accessibilityOptions ?? null,
    }),
    claim,
  };
}
