// Run: deno test classify_test.ts
import { classify, sanitizeSources, type Verdict } from "./classify.ts";
import { parsePoint } from "./geo.ts";

function assertEq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}: expected ${e}, got ${a}`);
}

function verdict(v: Partial<Verdict>): Verdict {
  return {
    image_confirms_barrier: null,
    barrier_type: null,
    venue_claims_accessible: null,
    web_corroboration_found: false,
    image_contradicts_report: false,
    confidence: "high",
    reasoning: "",
    sources: [],
    ...v,
  };
}

Deno.test("tier rules", () => {
  assertEq(
    classify(verdict({ image_contradicts_report: true })),
    { status: "rejected", tier: null },
    "contradicting photo rejects",
  );
  assertEq(
    classify(verdict({})),
    { status: "classified", tier: "unsubstantiated" },
    "description only",
  );
  assertEq(
    classify(verdict({ web_corroboration_found: true })),
    { status: "classified", tier: "unsubstantiated" },
    "corroboration without image stays unsubstantiated",
  );
  assertEq(
    classify(verdict({ image_confirms_barrier: true, venue_claims_accessible: true })),
    { status: "classified", tier: "partially_substantiated" },
    "image vs venue claim",
  );
  assertEq(
    classify(verdict({ image_confirms_barrier: true })),
    { status: "classified", tier: "substantiated" },
    "image, venue silent",
  );
  assertEq(
    classify(verdict({ image_confirms_barrier: true, venue_claims_accessible: false })),
    { status: "classified", tier: "substantiated" },
    "image, venue admits inaccessible",
  );
});

Deno.test("source sanitization", () => {
  const seen = new Set([
    "https://example.com/a",
    "https://maps.google.com/place",
  ]);

  assertEq(
    sanitizeSources(
      [
        { url: "https://example.com/a", title: "A", claim: "venue has stairs" },
        { url: "https://hallucinated.example/b", title: "B", claim: "made up" },
      ],
      seen,
    ),
    [{ url: "https://example.com/a", title: "A", claim: "venue has stairs" }],
    "hallucinated URLs are dropped",
  );

  assertEq(
    sanitizeSources(
      [
        { url: "https://example.com/a" },
        { url: "https://example.com/a", title: "dup" },
        { url: "https://maps.google.com/place", title: 42, claim: null },
      ],
      seen,
    ),
    [
      { url: "https://example.com/a", title: null, claim: null },
      { url: "https://maps.google.com/place", title: null, claim: null },
    ],
    "dedupes and normalizes non-string fields",
  );

  assertEq(sanitizeSources("not an array", seen), [], "non-array degrades to empty");
  assertEq(
    sanitizeSources([null, 7, { title: "no url" }], seen),
    [],
    "malformed entries are dropped",
  );
});

Deno.test("EWKB point decoding", () => {
  // Build EWKB for POINT(151.2093 -33.8988) SRID=4326, little endian:
  // 01 | 01000020 | E6100000 | x float64 | y float64
  const buf = new ArrayBuffer(25);
  const view = new DataView(buf);
  view.setUint8(0, 1);
  view.setUint32(1, 0x20000001, true); // point type + SRID flag
  view.setUint32(5, 4326, true);
  view.setFloat64(9, 151.2093, true);
  view.setFloat64(17, -33.8988, true);
  const hex = [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  const p = parsePoint(hex);
  assertEq(Math.round(p.lng * 1e4) / 1e4, 151.2093, "lng");
  assertEq(Math.round(p.lat * 1e4) / 1e4, -33.8988, "lat");

  // GeoJSON shape still works.
  assertEq(
    parsePoint({ type: "Point", coordinates: [151.5, -33.5] }),
    { lat: -33.5, lng: 151.5 },
    "geojson",
  );

  // Garbage degrades to 0,0.
  assertEq(parsePoint("not-a-geom"), { lat: 0, lng: 0 }, "garbage");
});
