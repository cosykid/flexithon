// classify-report edge function.
// Invoke with {"report_id": "<uuid>"} right after a report is inserted, or
// {"sweep": true} to retry all pending reports older than 2 minutes.

// Inline jsr: import is the standard pattern for Supabase edge functions
// deployed without a deno.json.
// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import { runVerification } from "./aiClient.ts";
import { classify } from "./classify.ts";
import { parsePoint } from "./geo.ts";

const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const MAX_RETRIES = 3;
const MAX_PHOTO_BYTES = 4 * 1024 * 1024;

Deno.serve(async (req) => {
  let body: { report_id?: string; sweep?: boolean };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  if (body.sweep) {
    const cutoff = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    const { data: pending, error } = await supa
      .from("reports")
      .select("id")
      .eq("status", "pending")
      .lt("retry_count", MAX_RETRIES)
      .lt("created_at", cutoff)
      .limit(10);
    if (error) return json({ error: error.message }, 500);
    const results = [];
    for (const r of pending ?? []) {
      results.push({ id: r.id, ...(await processReport(r.id)) });
    }
    return json({ swept: results.length, results });
  }

  if (!body.report_id) return json({ error: "report_id or sweep required" }, 400);
  const result = await processReport(body.report_id);
  return json(result, result.ok ? 200 : 500);
});

async function processReport(reportId: string): Promise<{ ok: boolean; detail: string }> {
  const { data: report, error } = await supa
    .from("reports")
    .select("*, locations(*)")
    .eq("id", reportId)
    .single();
  if (error || !report) return { ok: false, detail: `report not found: ${error?.message}` };
  if (report.status !== "pending") return { ok: true, detail: "already processed" }; // idempotent

  try {
    const imageDataUri = report.photo_path ? await loadPhoto(report.photo_path) : null;

    const point = parsePoint(report.geog);
    const { verdict, toolCallLog, model } = await runVerification({
      description: report.description,
      imageDataUri,
      venueName: report.locations?.name ?? null,
      venueAddress: report.locations?.address ?? null,
      placeRef: report.locations?.place_ref ?? null,
      lat: point.lat,
      lng: point.lng,
    });

    // Untagged reports can't trigger the Places tool; fall back to the
    // venue claim cached on the location (seeded or from earlier reports)
    // so partial-vs-substantiated still classifies correctly.
    if (
      verdict.venue_claims_accessible === null &&
      typeof report.locations?.venue_claims_accessible === "boolean"
    ) {
      verdict.venue_claims_accessible = report.locations.venue_claims_accessible;
    }

    const { status, tier } = classify(verdict);

    const { error: updateErr } = await supa
      .from("reports")
      .update({
        status,
        tier,
        barrier_type: verdict.barrier_type,
        image_confirms_barrier: verdict.image_confirms_barrier,
        venue_claims_accessible: verdict.venue_claims_accessible,
        web_corroboration_found: verdict.web_corroboration_found,
        ai_reasoning: {
          model,
          reasoning: verdict.reasoning,
          confidence: verdict.confidence,
          tool_calls: toolCallLog,
        },
      })
      .eq("id", reportId);
    if (updateErr) return { ok: false, detail: `update failed: ${updateErr.message}` };

    // Source links live in their own table; the app fetches the URL from
    // there at click time. Replace-then-insert keeps retries idempotent.
    if (verdict.sources.length > 0) {
      await supa.from("report_sources").delete().eq("report_id", reportId);
      const { error: srcErr } = await supa.from("report_sources").insert(
        verdict.sources.map((s, i) => ({
          report_id: reportId,
          url: s.url,
          title: s.title,
          claim: s.claim,
          position: i,
        })),
      );
      // Non-fatal: the verdict is already committed; a report without
      // citations is still valid.
      if (srcErr) console.error(`report_sources insert failed: ${srcErr.message}`);
    }

    if (report.locations && verdict.venue_claims_accessible !== null) {
      await supa
        .from("locations")
        .update({ venue_claims_accessible: verdict.venue_claims_accessible })
        .eq("id", report.location_id);
    }

    // Enough classified reports here? Kick off venue-outreach drafting.
    // Fire-and-forget: drafting takes ~a minute and must not block or fail
    // this classification; draft-outreach re-checks the threshold itself.
    maybeTriggerOutreach(report.location_id);

    return { ok: true, detail: `classified: ${tier ?? status}` };
  } catch (e) {
    // Leave pending; the sweep path retries up to MAX_RETRIES.
    await supa
      .from("reports")
      .update({ retry_count: report.retry_count + 1 })
      .eq("id", reportId);
    return { ok: false, detail: `verification failed (retry ${report.retry_count + 1}): ${e}` };
  }
}

function maybeTriggerOutreach(locationId: string): void {
  fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/draft-outreach`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
    },
    body: JSON.stringify({ location_id: locationId }),
  }).catch((e) => console.error(`draft-outreach trigger failed: ${e}`));
}

async function loadPhoto(path: string): Promise<string | null> {
  const { data, error } = await supa.storage.from("report-photos").download(path);
  if (error || !data) return null;
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.byteLength > MAX_PHOTO_BYTES) return null; // defensive: client should have compressed
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return `data:image/jpeg;base64,${btoa(binary)}`;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
