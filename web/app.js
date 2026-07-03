/* CurbCut map app */

const COLORS = {
  good: '#0ca30c', warn: '#fab219', serious: '#ec835a', critical: '#d03b3b',
  fixed: '#2a78d6', pending: '#898781', ink: '#1A1712',
};

const STATUS_LABELS = {
  reported: 'Awaiting verification',
  verified: 'Verified — ready to send',
  sent: 'Sent to council',
  acknowledged: 'Council acknowledged',
  fixed: 'Fixed',
  rejected: 'Rejected',
};

const TIMELINE = ['reported', 'verified', 'sent', 'acknowledged', 'fixed'];
const OPEN_ISSUE = new Set(['reported', 'verified', 'sent', 'acknowledged']);

const state = {
  meta: { issueCategories: {}, featureCategories: {} },
  reports: [],
  filter: 'all',
  map: null,
  layer: null,
  tempMarker: null,
  placing: false,
  draft: null, // { photo, lat, lng, accuracy, kind, submitting }
};

/* ---------- tiny safe DOM builder ---------- */
function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined || v === false) continue;
    if (k === 'class') node.className = v;
    else if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    node.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return node;
}

async function api(path, options) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`);
  return body;
}

function toast(message, kind = '') {
  const t = el('div', { class: `toast ${kind}`, role: 'status' }, message);
  document.getElementById('toasts').append(t);
  setTimeout(() => t.remove(), 4600);
}

function categoryLabelOf(r) {
  const table = r.kind === 'feature' ? state.meta.featureCategories : state.meta.issueCategories;
  return table[r.category] || r.category;
}

function shortAddress(r) {
  if (!r.address) return `${r.lat.toFixed(5)}, ${r.lng.toFixed(5)}`;
  return r.address.split(',').slice(0, 2).join(',');
}

function severityClass(sev) {
  if (sev >= 4) return 'critical';
  if (sev === 3) return 'serious';
  return 'warn';
}

function daysAgo(iso) {
  return Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 86400000));
}

/* ---------- map ---------- */
function initMap() {
  state.map = L.map('map', { zoomControl: true }).setView([51.5045, -0.113], 15);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  }).addTo(state.map);
  state.layer = L.layerGroup().addTo(state.map);

  navigator.geolocation?.getCurrentPosition(
    (p) => state.map.setView([p.coords.latitude, p.coords.longitude], 16),
    () => {},
    { timeout: 4000 },
  );

  state.map.on('click', (e) => {
    if (!state.placing) return;
    setDraftLocation(e.latlng.lat, e.latlng.lng, null);
  });
}

function markerStyleFor(r) {
  if (r.kind === 'feature') return { fill: COLORS.good, radius: 8 };
  if (r.status === 'fixed') return { fill: COLORS.fixed, radius: 7 };
  if (r.status === 'reported') return { fill: COLORS.pending, radius: 7, dash: '3 5' };
  const cls = severityClass(r.severity || 3);
  return {
    fill: COLORS[cls],
    radius: cls === 'critical' ? 11 : cls === 'serious' ? 9 : 8,
  };
}

function matchesFilter(r) {
  switch (state.filter) {
    case 'issues': return r.kind === 'issue' && OPEN_ISSUE.has(r.status);
    case 'features': return r.kind === 'feature' && r.status !== 'rejected';
    case 'pending': return r.status === 'reported';
    case 'fixed': return r.status === 'fixed';
    default: return r.status !== 'rejected';
  }
}

function renderMarkers() {
  state.layer.clearLayers();
  let shown = 0;
  for (const r of state.reports) {
    if (!matchesFilter(r)) continue;
    shown++;
    const s = markerStyleFor(r);
    const marker = L.circleMarker([r.lat, r.lng], {
      radius: s.radius,
      color: COLORS.ink,
      weight: 2,
      fillColor: s.fill,
      fillOpacity: 0.92,
      dashArray: s.dash,
    });
    marker.bindTooltip(`${categoryLabelOf(r)} · ${STATUS_LABELS[r.status] || r.status}`, {
      direction: 'top', className: 'cc-tip', offset: [0, -6],
    });
    marker.on('click', () => openDetail(r.id));
    marker.addTo(state.layer);
  }
  document.getElementById('chipCount').textContent = `${shown} shown`;
}

function fitToReports() {
  const pts = state.reports.filter(matchesFilter).map((r) => [r.lat, r.lng]);
  if (pts.length) state.map.fitBounds(L.latLngBounds(pts).pad(0.18), { maxZoom: 16 });
}

/* ---------- panel ---------- */
const panel = document.getElementById('panel');

function showPanel(title, subtitle, ...content) {
  panel.replaceChildren(
    el('div', { class: 'panel-head' },
      el('h2', {}, title),
      el('button', { class: 'panel-close', 'aria-label': 'Close panel', onclick: closePanel }, '✕'),
    ),
    subtitle ? el('p', { class: 'panel-sub' }, subtitle) : null,
    ...content,
  );
  panel.hidden = false;
  panel.scrollTop = 0;
}

function closePanel() {
  panel.hidden = true;
  state.placing = false;
  state.draft = null;
  if (state.tempMarker) { state.tempMarker.remove(); state.tempMarker = null; }
  if (location.hash) history.replaceState(null, '', location.pathname);
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !panel.hidden) closePanel();
});

/* ---------- report form ---------- */
function compressImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const scale = Math.min(1, 1400 / Math.max(img.width, img.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(img.width * scale);
      canvas.height = Math.round(img.height * scale);
      canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
      URL.revokeObjectURL(url);
      resolve(canvas.toDataURL('image/jpeg', 0.82));
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Could not read that image')); };
    img.src = url;
  });
}

function setDraftLocation(lat, lng, accuracy) {
  if (!state.draft) return;
  state.draft.lat = lat;
  state.draft.lng = lng;
  state.draft.accuracy = accuracy;

  if (!state.tempMarker) {
    state.tempMarker = L.marker([lat, lng], {
      draggable: true,
      icon: L.divIcon({ className: 'temp-pin', html: '<div class="temp-pin-inner"></div>', iconSize: [26, 26], iconAnchor: [13, 26] }),
    }).addTo(state.map);
    state.tempMarker.on('dragend', () => {
      const p = state.tempMarker.getLatLng();
      setDraftLocation(p.lat, p.lng, null);
    });
  } else {
    state.tempMarker.setLatLng([lat, lng]);
  }

  const line = document.getElementById('locLine');
  if (line) {
    line.classList.add('is-set');
    line.replaceChildren(
      '📍 ',
      accuracy
        ? `Using your location (±${Math.round(accuracy)}m) — drag the pin or tap the map to adjust`
        : 'Pin placed — drag it or tap the map to adjust',
    );
  }
  const submit = document.getElementById('submitBtn');
  if (submit) submit.disabled = false;
}

function categoryOptions(kind) {
  const table = kind === 'feature' ? state.meta.featureCategories : state.meta.issueCategories;
  return Object.entries(table).map(([value, label]) => el('option', { value }, label));
}

function openReportForm(photoDataUrl) {
  state.draft = { photo: photoDataUrl, lat: null, lng: null, kind: 'issue' };
  state.placing = true;

  const savedName = localStorage.getItem('curbcut-name') || '';

  const kindSeg = el('div', { class: 'seg', role: 'group', 'aria-label': 'Report type' },
    el('button', { type: 'button', class: 'is-on', id: 'kindIssue', onclick: () => setKind('issue') }, '⚠ Barrier'),
    el('button', { type: 'button', id: 'kindFeature', onclick: () => setKind('feature') }, '✓ Accessible feature'),
  );

  const categorySelect = el('select', { id: 'categorySelect' }, categoryOptions('issue'));

  function setKind(kind) {
    state.draft.kind = kind;
    document.getElementById('kindIssue').classList.toggle('is-on', kind === 'issue');
    document.getElementById('kindFeature').classList.toggle('is-on', kind === 'feature');
    categorySelect.replaceChildren(...categoryOptions(kind));
    document.getElementById('descInput').placeholder = kind === 'issue'
      ? 'e.g. No dropped kerb — wheelchair users forced onto the road'
      : 'e.g. Level entrance with automatic doors, lift to all floors';
    document.getElementById('submitBtn').textContent =
      kind === 'issue' ? 'Verify & report barrier' : 'Verify & add to map';
  }

  showPanel(
    'New report', 'Photo → AI check → on the map. Barriers also get a ready-to-send council letter.',
    el('img', { class: 'photo-preview', src: photoDataUrl, alt: 'Your photo' }),
    el('label', { for: 'kindIssue' }, 'What are you reporting?'),
    kindSeg,
    el('label', { for: 'categorySelect' }, 'Category'),
    categorySelect,
    el('label', { for: 'descInput' }, 'What’s the situation?'),
    el('textarea', { id: 'descInput', maxlength: 2000, placeholder: 'e.g. No dropped kerb — wheelchair users forced onto the road' }),
    el('label', { for: 'nameInput' }, 'Your name (optional — signs the letter, earns points)'),
    el('input', { type: 'text', id: 'nameInput', maxlength: 60, value: savedName, placeholder: 'e.g. Maya' }),
    el('div', { class: 'loc-line', id: 'locLine' }, '⌖ Finding your location… or tap the map to place the pin'),
    el('button', { class: 'btn-primary', id: 'submitBtn', disabled: true, onclick: submitReport }, 'Verify & report barrier'),
  );

  navigator.geolocation?.getCurrentPosition(
    (p) => {
      setDraftLocation(p.coords.latitude, p.coords.longitude, p.coords.accuracy);
      state.map.setView([p.coords.latitude, p.coords.longitude], 17);
    },
    () => {
      const line = document.getElementById('locLine');
      if (line) line.replaceChildren('⌖ Location unavailable — tap the map to place the pin');
    },
    { enableHighAccuracy: true, timeout: 8000 },
  );
}

async function submitReport() {
  const d = state.draft;
  if (!d || d.lat === null) return;
  const btn = document.getElementById('submitBtn');
  btn.disabled = true;
  btn.replaceChildren(el('span', { class: 'spinner' }), 'Claude is checking the photo…');

  const reporter = document.getElementById('nameInput').value.trim();
  localStorage.setItem('curbcut-name', reporter);

  try {
    const body = {
      photo: d.photo,
      lat: d.lat,
      lng: d.lng,
      kind: d.kind,
      category: document.getElementById('categorySelect').value,
      description: document.getElementById('descInput').value.trim(),
      reporter,
    };
    const res = await api('/api/reports', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    await loadReports();
    loadLeaderboard();

    if (res.duplicate) {
      toast('Someone already reported this spot — your confirmation was added (+1)');
    } else if (res.report.status === 'verified') {
      toast(res.report.kind === 'issue'
        ? 'Verified ✓ — council letter drafted and pinned to the map'
        : 'Verified ✓ — accessible feature added to the map');
    } else {
      toast('Logged — the photo needs a human look before it goes live');
    }
    openDetail(res.report.id);
  } catch (err) {
    toast(err.message, 'err');
    btn.disabled = false;
    btn.replaceChildren(d.kind === 'issue' ? 'Verify & report barrier' : 'Verify & add to map');
  }
}

/* ---------- detail view ---------- */
function timelineNode(r) {
  if (r.kind === 'feature' || r.status === 'rejected') return null;
  const idx = TIMELINE.indexOf(r.status);
  return el('div', { class: 'timeline', 'aria-label': 'Report progress' },
    TIMELINE.map((s, i) => el('div', {
      class: `tstep ${i < idx ? 'done' : ''} ${i === idx ? 'done now' : ''}`,
    }, STATUS_LABELS[s].split(' ')[0])),
  );
}

function aiCard(r) {
  const kids = [
    el('h3', {}, 'AI assessment ', el('span', { class: `badge ${r.ai_mock ? 'demo' : ''}` }, r.ai_mock ? 'DEMO' : 'CLAUDE')),
  ];
  if (r.kind === 'issue' && r.severity) {
    const cls = severityClass(r.severity);
    kids.push(
      el('div', { class: 'meter', role: 'img', 'aria-label': `Severity ${r.severity} out of 5` },
        [1, 2, 3, 4, 5].map((i) => el('span', { class: i <= r.severity ? `on-${cls}` : '' })),
      ),
      el('div', { class: 'meter-label' },
        `Severity ${r.severity}/5 · ${cls === 'critical' ? 'severe' : cls === 'serious' ? 'serious' : 'minor'}`),
    );
  }
  if (r.summary) kids.push(el('p', {}, r.summary));
  if (r.hazards) kids.push(el('p', {}, '⚠ ', el('strong', {}, 'Hazard: '), r.hazards));
  if (r.affected?.length) kids.push(el('div', { class: 'gchips' }, r.affected.map((g) => el('span', { class: 'gchip' }, g))));
  if (r.fixes?.length) {
    kids.push(
      el('p', {}, el('strong', {}, r.kind === 'issue' ? 'Suggested fixes' : 'Why it helps')),
      el('ol', { class: 'fixlist' }, r.fixes.map((f) => el('li', {}, f))),
    );
  }
  if (typeof r.confidence === 'number' && !r.ai_mock) {
    kids.push(el('p', { class: 'conf' }, `Confidence ${(r.confidence * 100).toFixed(0)}%`));
  }
  return el('div', { class: 'aicard' }, kids);
}

function letterBox(r) {
  if (!r.letter) return null;
  const subject = `Accessibility barrier report — ${categoryLabelOf(r)}, ${shortAddress(r)}`;
  const mailto = `mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(r.letter)}`;
  return el('div', { class: 'letterbox-wrap' },
    el('details', { class: 'letterbox' },
      el('summary', {}, 'Council letter — drafted & ready'),
      el('pre', {}, r.letter),
    ),
    el('div', { class: 'btn-row' },
      el('button', {
        class: 'btn',
        onclick: (e) => {
          navigator.clipboard.writeText(r.letter).then(
            () => { e.target.textContent = 'Copied ✓'; setTimeout(() => (e.target.textContent = 'Copy letter'), 1800); },
            () => toast('Copy failed — open the letter and copy manually', 'err'),
          );
        },
      }, 'Copy letter'),
      el('a', { class: 'btn accent', href: mailto }, 'Open in email'),
    ),
  );
}

function detailActions(r) {
  const confirmed = localStorage.getItem(`curbcut-conf-${r.id}`);
  const buttons = [];

  buttons.push(el('button', {
    class: 'btn',
    disabled: Boolean(confirmed),
    onclick: async (e) => {
      try {
        const res = await api(`/api/reports/${r.id}/confirm`, { method: 'POST' });
        localStorage.setItem(`curbcut-conf-${r.id}`, '1');
        e.target.disabled = true;
        e.target.textContent = `Confirmed (${res.report.confirmations})`;
        const i = state.reports.findIndex((x) => x.id === r.id);
        if (i >= 0) state.reports[i] = res.report;
        toast('Thanks — confirmation added');
      } catch (err) { toast(err.message, 'err'); }
    },
  }, confirmed ? `Confirmed (${r.confirmations})` : `👍 Still there? Confirm (${r.confirmations})`));

  if (r.kind === 'issue' && r.status === 'verified') {
    buttons.push(el('button', {
      class: 'btn accent',
      onclick: async (e) => {
        e.target.disabled = true;
        try {
          await api(`/api/reports/${r.id}/status`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ status: 'sent' }),
          });
          await loadReports();
          toast('Marked as sent to the council');
          openDetail(r.id);
        } catch (err) { toast(err.message, 'err'); e.target.disabled = false; }
      },
    }, 'Mark as sent →'));
  }

  return el('div', { class: 'btn-row' }, buttons);
}

function openDetail(id) {
  const r = state.reports.find((x) => x.id === id);
  if (!r) return;
  history.replaceState(null, '', `#r=${id}`);
  state.placing = false;
  if (state.tempMarker) { state.tempMarker.remove(); state.tempMarker = null; }

  const s = markerStyleFor(r);
  const meta = [
    el('span', { class: 'pill' },
      el('span', {
        class: 'dot', 'aria-hidden': 'true',
        style: `background:${s.fill};${s.dash ? 'border-style:dashed;' : ''}`,
      }),
      STATUS_LABELS[r.status] || r.status),
    el('span', { class: 'pill' }, r.kind === 'feature' ? '✓ Accessible feature' : '⚠ Barrier'),
    el('span', { class: 'pill' }, `${daysAgo(r.created_at)}d ago`),
  ];
  if (r.reporter) meta.push(el('span', { class: 'pill' }, `by ${r.reporter}`));

  showPanel(
    categoryLabelOf(r), null,
    el('div', { class: 'pill-row' }, meta),
    el('img', { class: 'photo', src: r.photo, alt: `Photo of ${categoryLabelOf(r)}` }),
    el('p', { class: 'addr' }, '📍 ', r.address || `${r.lat.toFixed(5)}, ${r.lng.toFixed(5)}`),
    r.description ? el('p', { style: 'font-size:13.5px;margin:0 0 12px' }, '“', r.description, '”') : null,
    aiCard(r),
    letterBox(r),
    detailActions(r),
    timelineNode(r),
  );
  state.map.panTo([r.lat, r.lng]);
}

/* ---------- data loading ---------- */
async function loadReports() {
  const { reports } = await api('/api/reports');
  state.reports = reports;
  renderMarkers();
}

async function loadLeaderboard() {
  try {
    const stats = await api('/api/stats');
    const box = document.getElementById('leader');
    const list = document.getElementById('leaderList');
    if (!stats.leaderboard?.length) { box.hidden = true; return; }
    list.replaceChildren(...stats.leaderboard.slice(0, 3).map((p) =>
      el('li', {}, `${p.name} `, el('span', { class: 'pts' }, `${p.points} pts`)),
    ));
    box.hidden = false;
  } catch { /* non-critical */ }
}

/* ---------- wiring ---------- */
async function init() {
  initMap();

  document.querySelectorAll('.chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.chip').forEach((c) => {
        c.classList.toggle('is-on', c === chip);
        c.setAttribute('aria-pressed', String(c === chip));
      });
      state.filter = chip.dataset.filter;
      renderMarkers();
    });
  });

  const input = document.getElementById('cameraInput');
  document.getElementById('fab').addEventListener('click', () => { input.value = ''; input.click(); });
  input.addEventListener('change', async () => {
    const file = input.files?.[0];
    if (!file) return;
    try {
      openReportForm(await compressImage(file));
    } catch (err) {
      toast(err.message, 'err');
    }
  });

  state.meta = await api('/api/meta');
  await loadReports();
  loadLeaderboard();

  const hashId = location.hash.match(/^#r=(.+)$/)?.[1];
  if (hashId && state.reports.some((r) => r.id === hashId)) {
    const r = state.reports.find((x) => x.id === hashId);
    state.map.setView([r.lat, r.lng], 17);
    openDetail(hashId);
  } else if (state.reports.length) {
    fitToReports();
  } else {
    toast('No reports yet — tap “Report” to add the first one (or run: npm run seed)');
  }
}

init().catch((err) => toast(`Failed to load: ${err.message}`, 'err'));
