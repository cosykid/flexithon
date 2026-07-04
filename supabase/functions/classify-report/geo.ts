// PostgREST returns PostGIS geography columns as EWKB hex strings
// (e.g. "0101000020E6100000..."), not GeoJSON. Handle both, plus GeoJSON
// in case a cast/view is introduced later.
export function parsePoint(geog: unknown): { lat: number; lng: number } {
  if (typeof geog === "object" && geog !== null && "coordinates" in geog) {
    const [lng, lat] = (geog as { coordinates: [number, number] }).coordinates;
    return { lat, lng };
  }
  if (typeof geog === "string" && /^[0-9A-Fa-f]{42,}$/.test(geog)) {
    try {
      const bytes = new Uint8Array(
        geog.match(/../g)!.map((b) => parseInt(b, 16)),
      );
      const view = new DataView(bytes.buffer);
      const littleEndian = bytes[0] === 1;
      const type = view.getUint32(1, littleEndian);
      // Bit 0x20000000 flags an embedded SRID (4 extra bytes before coords).
      const offset = (type & 0x20000000) !== 0 ? 9 : 5;
      const lng = view.getFloat64(offset, littleEndian);
      const lat = view.getFloat64(offset + 8, littleEndian);
      if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
    } catch {
      // fall through
    }
  }
  return { lat: 0, lng: 0 };
}
