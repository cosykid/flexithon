// Claude-powered verification of accessibility reports.
//
// With credentials (ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN, or an `ant auth
// login` profile) each report's photo is assessed by Claude vision with a
// strict JSON schema output; for barriers it also drafts a formal letter to
// the responsible council / facility owner. Without credentials — or when
// CURBCUT_AI=mock — a deterministic mock keeps the demo fully functional.

import Anthropic from '@anthropic-ai/sdk';
import { AFFECTED_GROUPS } from './categories.js';
import { standardsFor, countryName } from './geocode.js';
import { templateLetter } from './letters.js';

// Read lazily — the .env loader in index.js runs after module imports.
const MODEL = () => process.env.ANTHROPIC_MODEL || 'claude-opus-4-8';
const AI_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

let client = null;
function getClient() {
  client ??= new Anthropic();
  return client;
}

export function aiForcedMock() {
  return process.env.CURBCUT_AI === 'mock';
}

const ISSUE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'verified', 'confidence', 'severity', 'summary', 'hazards',
    'affected_groups', 'suggested_fixes', 'letter',
  ],
  properties: {
    verified: {
      type: 'boolean',
      description: 'Does the photo plausibly show the reported barrier (or a closely related accessibility issue) at a real location?',
    },
    confidence: { type: 'number', description: 'Confidence in the verdict, 0 to 1.' },
    severity: {
      type: 'integer',
      enum: [1, 2, 3, 4, 5],
      description: '1 = minor inconvenience, 3 = significant barrier, 5 = complete blocker or safety hazard.',
    },
    summary: { type: 'string', description: 'One or two plain sentences describing what the photo shows.' },
    hazards: { type: 'string', description: 'Any immediate safety hazards, or an empty string.' },
    affected_groups: { type: 'array', items: { type: 'string', enum: AFFECTED_GROUPS } },
    suggested_fixes: {
      type: 'array',
      items: { type: 'string' },
      description: 'Concrete, feasible remediations, most important first (2-4 items).',
    },
    letter: {
      type: 'string',
      description: 'Formal report letter to the responsible council or facility owner. Plain text, no markdown. Empty string if not verified.',
    },
  },
};

const FEATURE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['verified', 'confidence', 'summary', 'benefits'],
  properties: {
    verified: {
      type: 'boolean',
      description: 'Does the photo plausibly show the reported accessible feature?',
    },
    confidence: { type: 'number', description: 'Confidence in the verdict, 0 to 1.' },
    summary: { type: 'string', description: 'One or two plain sentences describing the feature in the photo.' },
    benefits: {
      type: 'array',
      items: { type: 'string' },
      description: 'Who this helps and how (1-3 short items).',
    },
  },
};

function issuePrompt(r) {
  const where = r.address || `coordinates ${r.lat}, ${r.lng}`;
  const country = r.country ? ` in ${countryName(r.country)}` : '';
  return `You are the verification engine for CurbCut, a civic app where the public photographs accessibility barriers so they can be mapped and reported to the responsible authority.

A report was just submitted:
- Reported category: ${r.categoryLabel}
- Reporter's description: ${JSON.stringify(r.description || '(none)')}
- Location: ${where}${country}
- Date: ${new Date().toISOString().slice(0, 10)}

Assess the attached photo:
1. verified — true if the photo plausibly shows the reported barrier or a closely related accessibility problem. Be fair but not credulous: an unrelated photo, a meme, a screenshot, or an image with no visible accessibility issue is NOT verified.
2. severity — 1 (minor inconvenience) to 5 (complete blocker or safety hazard) for the people it affects.
3. affected_groups, hazards, summary — grounded in what is actually visible.
4. suggested_fixes — concrete, feasible remediations for the responsible authority, most important first.
5. letter — if verified, draft a formal, courteous report letter addressed "Dear Access and Inclusion Officer," from the reporter to the responsible council or facility owner. Include: what the barrier is and where (use the location above), a note that photographic evidence and GPS coordinates (${r.lat}, ${r.lng}) are attached, who it affects and why it matters, a reference to ${standardsFor(r.country)}, the requested remediation steps, and a request for acknowledgement with a reference number. Sign off as ${JSON.stringify(r.reporter || 'A community member')}, "Submitted via CurbCut — community accessibility mapping". Plain text only. If not verified, letter must be an empty string.`;
}

function featurePrompt(r) {
  const where = r.address || `coordinates ${r.lat}, ${r.lng}`;
  return `You are the verification engine for CurbCut, a civic app that maps accessible places and features so disabled people can plan routes with confidence.

A member of the public reported an accessible feature:
- Reported feature: ${r.categoryLabel}
- Reporter's description: ${JSON.stringify(r.description || '(none)')}
- Location: ${where}

Assess the attached photo: verified is true only if the photo plausibly shows the reported feature (or an equivalent accessible provision). Summarise what is visible and list who it helps.`;
}

function mockResult(r) {
  const severityByCategory = {
    'blocked-path': 4, 'no-ramp': 5, 'steep-ramp': 4, 'no-dropped-kerb': 4,
    'broken-lift': 5, 'narrow-door': 3, 'no-tactile': 3,
    'no-accessible-toilet': 4, 'bad-parking': 3, 'poor-surface': 3, 'other': 3,
  };
  const fixesByCategory = {
    'blocked-path': ['Remove or relocate the obstruction', 'Enforce keep-clear rules for the footpath'],
    'no-ramp': ['Install a compliant ramp (gradient 1:14 or gentler)', 'Signpost the nearest step-free alternative in the interim'],
    'steep-ramp': ['Rebuild the ramp to a compliant gradient with handrails', 'Add landings and edge protection'],
    'no-dropped-kerb': ['Install a dropped kerb with tactile paving on both sides of the crossing'],
    'broken-lift': ['Repair the lift and publish a maintenance schedule', 'Provide staffed assistance while out of service'],
    'narrow-door': ['Widen the doorway to at least 850mm clear opening', 'Fit an automatic door opener'],
    'no-tactile': ['Install tactile warning paving at the crossing or platform edge'],
    'no-accessible-toilet': ['Provide an accessible toilet or signpost the nearest one within reasonable distance'],
    'bad-parking': ['Repaint and enforce the accessible bay to standard dimensions', 'Add a dropped kerb from the bay to the footway'],
    'poor-surface': ['Resurface the damaged section to a firm, level finish'],
    'other': ['Inspect the site and remediate the reported barrier'],
  };

  if (r.kind === 'feature') {
    return {
      verified: true,
      confidence: 0.5,
      severity: null,
      summary: `Demo verification: recorded as "${r.categoryLabel}" from the reporter's photo and description.`,
      hazards: '',
      affected: ['wheelchair users', 'people with limited mobility'],
      fixes: ['Helps wheelchair users and anyone who needs step-free access plan this route with confidence.'],
      letter: '',
      mock: true,
    };
  }

  const severity = severityByCategory[r.category] ?? 3;
  const fixes = fixesByCategory[r.category] ?? fixesByCategory.other;
  const affected = ['wheelchair users', 'people with limited mobility', 'older people'];
  return {
    verified: true,
    confidence: 0.5,
    severity,
    summary: `Demo verification: recorded as "${r.categoryLabel}" from the reporter's photo and description.`,
    hazards: severity >= 4 ? 'Potential safety hazard — people may be forced onto the road or into unsafe detours.' : '',
    affected,
    fixes,
    letter: templateLetter({
      id: r.id,
      categoryLabel: r.categoryLabel,
      description: r.description,
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      severity,
      affected,
      fixes,
      standards: standardsFor(r.country),
      reporter: r.reporter,
    }),
    mock: true,
  };
}

// r: { id, kind, category, categoryLabel, description, reporter, lat, lng,
//      address, country, imageBase64, mediaType }
export async function verifyReport(r) {
  if (aiForcedMock() || !AI_IMAGE_TYPES.has(r.mediaType)) return mockResult(r);

  const isIssue = r.kind !== 'feature';
  try {
    const response = await getClient().messages.create({
      model: MODEL(),
      max_tokens: 16000,
      thinking: { type: 'adaptive' },
      output_config: {
        format: { type: 'json_schema', schema: isIssue ? ISSUE_SCHEMA : FEATURE_SCHEMA },
      },
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: r.mediaType, data: r.imageBase64 },
            },
            { type: 'text', text: isIssue ? issuePrompt(r) : featurePrompt(r) },
          ],
        },
      ],
    });

    if (response.stop_reason === 'refusal') throw new Error('model refused the request');
    const textBlock = response.content.find((b) => b.type === 'text');
    if (!textBlock) throw new Error(`no text block (stop_reason: ${response.stop_reason})`);
    const out = JSON.parse(textBlock.text);

    return {
      verified: out.verified,
      confidence: Math.max(0, Math.min(1, out.confidence ?? 0)),
      severity: isIssue ? out.severity : null,
      summary: out.summary || '',
      hazards: isIssue ? out.hazards || '' : '',
      affected: isIssue ? out.affected_groups || [] : [],
      fixes: isIssue ? out.suggested_fixes || [] : out.benefits || [],
      letter: isIssue ? out.letter || '' : '',
      mock: false,
    };
  } catch (err) {
    console.error(`[ai] verification failed, falling back to demo mode: ${err.message}`);
    const fallback = mockResult(r);
    fallback.summary += ` (Live AI unavailable: ${err.message})`;
    return fallback;
  }
}
