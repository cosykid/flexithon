// draft-outreach edge function.
// Invoke with {"location_id": "<uuid>"} once a location has enough classified
// reports. Finds the venue's contact email, copies report photos to the
// public outreach-photos bucket, and stores a ready-to-send draft in
// location_outreach. Idempotent: re-drafts only when >=2 new reports landed
// since the last draft.

// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import { parsePoint } from "./geo.ts";
import { runOutreach } from "./outreachAgent.ts";

const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Matches the app's 5-report auto-promotion story: outreach unlocks at the
// same scale the map pin turns red.
const MIN_REPORTS = 5;
const REDRAFT_DELTA = 2;
const MAX_PHOTOS = 4;

Deno.serve(async (req) => {
  let body: { location_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.location_id) return json({ error: "location_id required" }, 400);

  const result = await processLocation(body.location_id);
  return json(result, result.ok ? 200 : 500);
});

async function processLocation(locationId: string): Promise<{ ok: boolean; detail: string }> {
  const { data: location, error: locErr } = await supa
    .from("locations")
    .select("*")
    .eq("id", locationId)
    .single();
  if (locErr || !location) return { ok: false, detail: `location not found: ${locErr?.message}` };

  const { data: reports, error: repErr } = await supa
    .from("reports")
    .select("id, description, barrier_type, photo_path, created_at, tier")
    .eq("location_id", locationId)
    .eq("status", "classified")
    .in("tier", ["partially_substantiated", "substantiated"])
    .order("created_at", { ascending: false });
  if (repErr) return { ok: false, detail: repErr.message };
  if (!reports || reports.length < MIN_REPORTS) {
    return { ok: true, detail: `skipped: ${reports?.length ?? 0}/${MIN_REPORTS} reports` };
  }

  const { data: existing } = await supa
    .from("location_outreach")
    .select("status, report_count, updated_at")
    .eq("location_id", locationId)
    .maybeSingle();
  if (existing && reports.length - existing.report_count < REDRAFT_DELTA) {
    // failed → always retry. pending → only a fresh one blocks (a worker
    // that died mid-draft leaves pending behind; stale rows are taken over).
    const staleMs = Date.now() - new Date(existing.updated_at).getTime();
    const blocks = existing.status === "drafted" ||
      existing.status === "no_email_found" ||
      (existing.status === "pending" && staleMs < 10 * 60 * 1000);
    if (blocks) {
      return { ok: true, detail: `already ${existing.status} at ${existing.report_count} reports` };
    }
  }

  await supa.from("location_outreach").upsert({
    location_id: locationId,
    status: "pending",
    report_count: reports.length,
    updated_at: new Date().toISOString(),
  });

  try {
    const photoUrls = await publishPhotos(locationId, reports);

    const dates = reports.map((r) => new Date(r.created_at).getTime());
    const fmt = (t: number) => new Date(t).toISOString().slice(0, 10);
    const barrierCounts = new Map<string, number>();
    for (const r of reports) {
      const b = r.barrier_type ?? "unspecified";
      barrierCounts.set(b, (barrierCounts.get(b) ?? 0) + 1);
    }

    // Untagged locations have no name — the agent identifies the venue from
    // GPS via find_nearby_venues, or bails with email null if ambiguous.
    const point = parsePoint(location.geog);
    const draft = await runOutreach({
      venueName: location.name,
      venueAddress: location.address,
      lat: point.lat,
      lng: point.lng,
      reportCount: reports.length,
      dateRange: `${fmt(Math.min(...dates))} to ${fmt(Math.max(...dates))}`,
      barrierSummary: [...barrierCounts].map(([b, n]) => `${b} (${n})`).join(", "),
      descriptions: reports.slice(0, 8).map((r) => String(r.description).slice(0, 200)),
    });

    const bodyWithPhotos = photoUrls.length > 0
      ? `${draft.body}\n\nPhotos from the reports:\n${photoUrls.join("\n")}`
      : draft.body;

    const { error: upErr } = await supa.from("location_outreach").upsert({
      location_id: locationId,
      status: draft.email ? "drafted" : "no_email_found",
      business_email: draft.email,
      email_source_url: draft.emailSourceUrl,
      subject: draft.subject,
      body: bodyWithPhotos,
      photo_urls: photoUrls,
      model: draft.model,
      report_count: reports.length,
      updated_at: new Date().toISOString(),
    });
    if (upErr) return { ok: false, detail: `save failed: ${upErr.message}` };

    return { ok: true, detail: draft.email ? `drafted for ${draft.email}` : "drafted, no email found" };
  } catch (e) {
    await supa.from("location_outreach").upsert({
      location_id: locationId,
      status: "failed",
      report_count: reports.length,
      updated_at: new Date().toISOString(),
    });
    return { ok: false, detail: `draft failed: ${e}` };
  }
}

/// Copy up to MAX_PHOTOS report photos into the public bucket so email
/// recipients can open them without auth. Upsert keeps re-drafts idempotent.
async function publishPhotos(
  locationId: string,
  reports: Array<{ photo_path: string | null }>,
): Promise<string[]> {
  const urls: string[] = [];
  const withPhotos = reports.filter((r) => r.photo_path).slice(0, MAX_PHOTOS);
  for (let i = 0; i < withPhotos.length; i++) {
    const src = withPhotos[i].photo_path!;
    const { data, error } = await supa.storage.from("report-photos").download(src);
    if (error || !data) continue;
    const dest = `${locationId}/${i + 1}.jpg`;
    const { error: upErr } = await supa.storage
      .from("outreach-photos")
      .upload(dest, data, { contentType: "image/jpeg", upsert: true });
    if (upErr) continue;
    const { data: pub } = supa.storage.from("outreach-photos").getPublicUrl(dest);
    if (pub?.publicUrl) urls.push(pub.publicUrl);
  }
  return urls;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
