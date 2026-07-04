// Minimal OpenAI-compatible chat client with a tool-use loop.
// Works against any /chat/completions endpoint that supports vision + tools.

import { toolDefinitions, webSearch, getPlaceAccessibility } from "./tools.ts";
import type { Verdict } from "./classify.ts";

const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ?? "https://api.openai.com/v1")
  .replace(/\/$/, "");
const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
const AI_MODEL = Deno.env.get("AI_MODEL") ?? "gpt-4o-mini";

const MAX_ITERATIONS = 5;
const DEADLINE_MS = 60_000;

const SYSTEM_PROMPT = `You verify crowdsourced accessibility-barrier reports for wheelchair users.
Examine the photo if provided: does it clearly show the claimed barrier (stairs, missing ramp, narrow doorway, broken lift, etc.)?
If a venue is tagged (place_id given), call get_place_accessibility to check the venue's own accessibility claim.
Optionally call web_search (e.g. "<venue name> <address> wheelchair accessible") to corroborate the barrier claim.
Then call submit_verdict exactly once. You report facts only; you do not decide the report's classification.`;

interface RunInput {
  description: string;
  imageDataUri: string | null;
  venueName: string | null;
  venueAddress: string | null;
  placeRef: string | null;
  lat: number;
  lng: number;
}

export interface RunResult {
  verdict: Verdict;
  toolCallLog: Array<{ tool: string; args: unknown }>;
  model: string;
}

export async function runVerification(input: RunInput): Promise<RunResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEADLINE_MS);
  try {
    return await runLoop(input, controller.signal);
  } finally {
    clearTimeout(timer);
  }
}

async function runLoop(input: RunInput, signal: AbortSignal): Promise<RunResult> {
  const userContent: unknown[] = [
    {
      type: "text",
      text:
        `Report description: ${input.description}\n` +
        `GPS: ${input.lat}, ${input.lng}\n` +
        (input.venueName
          ? `Tagged venue: ${input.venueName}${input.venueAddress ? `, ${input.venueAddress}` : ""} (place_id: ${input.placeRef})`
          : "No venue tagged.") +
        (input.imageDataUri ? "" : "\nNo photo was provided with this report."),
    },
  ];
  if (input.imageDataUri) {
    userContent.push({ type: "image_url", image_url: { url: input.imageDataUri } });
  }

  // deno-lint-ignore no-explicit-any
  const messages: any[] = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: userContent },
  ];

  const toolCallLog: Array<{ tool: string; args: unknown }> = [];
  // Ground truth from the Places tool; overrides the model's echo in the verdict.
  let placesClaim: boolean | null | undefined;
  let visionRetried = false;

  for (let i = 0; i < MAX_ITERATIONS; i++) {
    let res: Response;
    try {
      res = await chatCompletion(messages, signal);
    } catch (e) {
      throw new Error(`AI endpoint unreachable: ${e}`);
    }

    if (!res.ok) {
      const body = await res.text();
      // Vision-less endpoint fallback: retry once without the image so the
      // report degrades to unsubstantiated instead of sticking pending.
      if (!visionRetried && input.imageDataUri && res.status === 400) {
        visionRetried = true;
        messages[1] = {
          role: "user",
          content: (userContent[0] as { text: string }).text +
            "\n(The photo could not be processed; treat this as if no photo was provided.)",
        };
        continue;
      }
      throw new Error(`AI endpoint error ${res.status}: ${body.slice(0, 300)}`);
    }

    const data = await res.json();
    const msg = data.choices?.[0]?.message;
    if (!msg) throw new Error("AI endpoint returned no message");

    const toolCalls = msg.tool_calls ?? [];
    if (toolCalls.length === 0) {
      // No tool call — nudge once, then give up.
      messages.push(msg, {
        role: "user",
        content: "You must call submit_verdict with your findings.",
      });
      continue;
    }

    messages.push(msg);
    for (const tc of toolCalls) {
      const name = tc.function?.name;
      let args: Record<string, unknown> = {};
      try {
        args = JSON.parse(tc.function?.arguments ?? "{}");
      } catch {
        // fall through with empty args
      }
      toolCallLog.push({ tool: name, args });

      if (name === "submit_verdict") {
        const verdict = normalizeVerdict(args, input, visionRetried);
        if (placesClaim !== undefined) verdict.venue_claims_accessible = placesClaim;
        return { verdict, toolCallLog, model: AI_MODEL };
      }

      let result: string;
      if (name === "web_search") {
        result = await webSearch(String(args.query ?? ""));
      } else if (name === "get_place_accessibility") {
        const out = await getPlaceAccessibility(String(args.place_id ?? ""));
        placesClaim = out.claim;
        result = out.raw;
      } else {
        result = JSON.stringify({ error: `unknown tool ${name}` });
      }
      messages.push({ role: "tool", tool_call_id: tc.id, content: result });
    }
  }

  throw new Error("verification loop exceeded max iterations without a verdict");
}

function chatCompletion(messages: unknown[], signal: AbortSignal): Promise<Response> {
  return fetch(`${AI_BASE_URL}/chat/completions`, {
    method: "POST",
    signal,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${AI_API_KEY}`,
    },
    body: JSON.stringify({
      model: AI_MODEL,
      messages,
      tools: toolDefinitions,
      tool_choice: "auto",
      temperature: 0,
    }),
  });
}

function normalizeVerdict(
  args: Record<string, unknown>,
  input: RunInput,
  visionFailed: boolean,
): Verdict {
  const noImage = !input.imageDataUri || visionFailed;
  return {
    image_confirms_barrier: noImage
      ? null
      : typeof args.image_confirms_barrier === "boolean"
      ? args.image_confirms_barrier
      : null,
    barrier_type: typeof args.barrier_type === "string" ? args.barrier_type : null,
    venue_claims_accessible: typeof args.venue_claims_accessible === "boolean"
      ? args.venue_claims_accessible
      : null,
    web_corroboration_found: args.web_corroboration_found === true,
    image_contradicts_report: !noImage && args.image_contradicts_report === true,
    confidence: (["low", "medium", "high"].includes(String(args.confidence))
      ? args.confidence
      : "low") as Verdict["confidence"],
    reasoning: String(args.reasoning ?? ""),
  };
}
