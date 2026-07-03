// Shared vocabulary for reports. Keys are stored in the DB; labels are shown in UIs
// and passed to the AI verifier.

export const ISSUE_CATEGORIES = {
  'blocked-path': 'Blocked footpath',
  'no-ramp': 'No ramp / steps only',
  'steep-ramp': 'Ramp too steep or unsafe',
  'no-dropped-kerb': 'Missing dropped kerb',
  'broken-lift': 'Broken or missing lift',
  'narrow-door': 'Door or gate too narrow',
  'no-tactile': 'Missing tactile paving',
  'no-accessible-toilet': 'No accessible toilet',
  'bad-parking': 'Accessible parking problem',
  'poor-surface': 'Broken or uneven surface',
  'other': 'Other barrier',
};

export const FEATURE_CATEGORIES = {
  'step-free': 'Step-free entrance',
  'ramp': 'Good ramp',
  'lift': 'Working lift',
  'accessible-toilet': 'Accessible toilet',
  'accessible-parking': 'Accessible parking',
  'tactile': 'Tactile paving',
  'hearing-loop': 'Hearing loop',
  'other': 'Other accessible feature',
};

export const AFFECTED_GROUPS = [
  'wheelchair users',
  'people with limited mobility',
  'blind and low-vision people',
  'Deaf and hard-of-hearing people',
  'older people',
  'people with prams or strollers',
  'people with cognitive disabilities',
];

export const STATUSES = ['reported', 'verified', 'sent', 'acknowledged', 'fixed', 'rejected'];

export function categoryLabel(kind, key) {
  const table = kind === 'feature' ? FEATURE_CATEGORIES : ISSUE_CATEGORIES;
  return table[key] || key;
}
