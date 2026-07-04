// Deterministic tier rules. The model reports facts; this code decides.
// The >=5-partials promotion is NOT here — it's the DB trigger on locations.

export interface Source {
  url: string;
  title: string | null;
  claim: string | null;
}

export interface Verdict {
  image_confirms_barrier: boolean | null;
  barrier_type: string | null;
  venue_claims_accessible: boolean | null;
  web_corroboration_found: boolean;
  image_contradicts_report: boolean;
  confidence: "low" | "medium" | "high";
  reasoning: string;
  sources: Source[];
}

// Model-cited sources are only trusted when the URL actually appeared in a
// tool result during this run — a hallucinated link is worse than no link.
export function sanitizeSources(
  raw: unknown,
  seenUrls: ReadonlySet<string>,
): Source[] {
  if (!Array.isArray(raw)) return [];
  const out: Source[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const { url, title, claim } = item as Record<string, unknown>;
    if (typeof url !== "string" || !seenUrls.has(url)) continue;
    if (out.some((s) => s.url === url)) continue;
    out.push({
      url,
      title: typeof title === "string" ? title : null,
      claim: typeof claim === "string" ? claim : null,
    });
  }
  return out;
}

export function classify(v: Verdict): { status: string; tier: string | null } {
  if (v.image_contradicts_report) {
    return { status: "rejected", tier: null };
  }
  // A confirming image is the prerequisite for any map-visible tier.
  if (v.image_confirms_barrier !== true) {
    return { status: "classified", tier: "unsubstantiated" };
  }
  if (v.venue_claims_accessible === true) {
    return { status: "classified", tier: "partially_substantiated" };
  }
  // Venue claims nothing, or explicitly claims inaccessibility.
  return { status: "classified", tier: "substantiated" };
}
