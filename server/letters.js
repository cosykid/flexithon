// Template letter used in demo mode (no API key) and by the seed script.
// With a key, Claude drafts a bespoke letter instead.

export function templateLetter({
  id, categoryLabel, description, address, lat, lng, severity, affected,
  fixes, standards, reporter,
}) {
  const where = address || `GPS ${lat}, ${lng}`;
  const groups = (affected || []).join(', ') || 'disabled and mobility-impaired people';
  const actions = (fixes || []).map((f, i) => `  ${i + 1}. ${f}`).join('\n') ||
    '  1. Inspect the site and remediate the barrier described above.';
  return `Dear Access and Inclusion Officer,

I am writing to report an accessibility barrier in your area.

Issue: ${categoryLabel}
Location: ${where}
GPS coordinates: ${lat}, ${lng}
Severity: ${severity ?? '-'} out of 5
Reporter's description: ${description || '(none provided)'}

This barrier primarily affects ${groups}. Photographic evidence is attached to this report (CurbCut reference ${id}).

Under ${standards}, public bodies and service providers are expected to provide and maintain reasonable access to the built environment. I therefore request that you:

${actions}

Please acknowledge receipt of this report and provide a reference number so the community can track its resolution.

Kind regards,
${reporter || 'A community member'}
Submitted via CurbCut — community accessibility mapping`;
}
