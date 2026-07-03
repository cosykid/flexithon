// Reverse geocoding via Nominatim (OpenStreetMap) + per-country accessibility
// standards used when drafting letters to councils / facility owners.

const STANDARDS = {
  GB: 'the Equality Act 2010 and BS 8300 (Design of an accessible and inclusive built environment)',
  US: 'the Americans with Disabilities Act (ADA) and the 2010 ADA Standards for Accessible Design',
  AU: 'the Disability Discrimination Act 1992 and AS 1428.1 (Design for access and mobility)',
  NZ: 'the Building Act 2004 and NZS 4121 (Design for access and mobility)',
  CA: 'the Accessible Canada Act and applicable provincial accessibility standards',
  IE: 'the Disability Act 2005 and Part M of the Building Regulations',
  SG: 'the BCA Code on Accessibility in the Built Environment',
  MY: 'MS 1184 (Universal design and accessibility in the built environment)',
  DE: 'the Behindertengleichstellungsgesetz (BGG) and DIN 18040',
  FR: 'the loi handicap of 11 February 2005',
};

export function standardsFor(countryCode) {
  return STANDARDS[countryCode] || 'applicable accessibility legislation and standards';
}

export function countryName(code) {
  if (!code) return '';
  try {
    return new Intl.DisplayNames(['en'], { type: 'region' }).of(code) || code;
  } catch {
    return code;
  }
}

export async function reverseGeocode(lat, lng) {
  try {
    const url =
      'https://nominatim.openstreetmap.org/reverse?format=jsonv2' +
      `&lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lng)}&zoom=18&addressdetails=1`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'curbcut-demo/0.1 (hackathon prototype)' },
      signal: AbortSignal.timeout(6000),
    });
    if (!res.ok) throw new Error(`nominatim ${res.status}`);
    const j = await res.json();
    return {
      address: j.display_name || '',
      country: (j.address?.country_code || '').toUpperCase(),
    };
  } catch {
    return { address: '', country: '' };
  }
}
