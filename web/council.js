/* CurbCut council dashboard */

const STATUS_ORDER = { verified: 0, sent: 1, acknowledged: 2, reported: 3, fixed: 4, rejected: 5 };

let meta = { issueCategories: {}, featureCategories: {}, statuses: [] };

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
  setTimeout(() => t.remove(), 4000);
}

const label = (r) =>
  (r.kind === 'feature' ? meta.featureCategories : meta.issueCategories)[r.category] || r.category;
const shortAddress = (r) =>
  r.address ? r.address.split(',').slice(0, 2).join(',') : `${r.lat.toFixed(4)}, ${r.lng.toFixed(4)}`;
const daysAgo = (iso) => Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 86400000));

function renderTiles(stats) {
  const tiles = [
    ['Open barriers', stats.openIssues, 'reported · verified · sent · acknowledged'],
    ['Median days open', stats.medianDaysOpen, 'across open barriers'],
    ['Fixed', stats.fixed, 'barriers resolved'],
    ['Community confirmations', stats.confirmations, '“still there” votes across reports'],
  ];
  document.getElementById('tiles').replaceChildren(
    ...tiles.map(([t, v, sub]) => el('div', { class: 'tile card' },
      el('div', { class: 't-label' }, t),
      el('div', { class: 't-value' }, String(v)),
      el('div', { class: 't-sub' }, sub),
    )),
  );
}

function renderBars(stats) {
  const entries = Object.entries(stats.byCategory).sort((a, b) => b[1] - a[1]);
  const box = document.getElementById('bars');
  if (!entries.length) {
    box.replaceChildren(el('p', { style: 'color:var(--ink-3);font-size:13.5px' }, 'No open barriers — nice work.'));
    return;
  }
  const max = entries[0][1];
  box.replaceChildren(...entries.map(([cat, n]) =>
    el('div', { class: 'bar-row' },
      el('div', { class: 'bar-label' }, meta.issueCategories[cat] || cat),
      el('div', { class: 'bar-track' },
        el('div', { class: 'bar-fill', style: `width:${(n / max) * 100}%` })),
      el('div', { class: 'bar-count' }, String(n)),
    ),
  ));
}

function sevTag(r) {
  if (r.kind === 'feature' || !r.severity) return el('span', {}, '—');
  const cls = r.severity >= 4 ? 'sev-critical' : r.severity === 3 ? 'sev-serious' : 'sev-warn';
  return el('span', { class: `sev-tag ${cls}` }, String(r.severity));
}

function statusSelect(r) {
  const select = el('select', { 'aria-label': `Status for ${label(r)}` },
    meta.statuses.map((s) => el('option', { value: s, selected: s === r.status || null }, s)),
  );
  select.addEventListener('change', async () => {
    select.disabled = true;
    try {
      await api(`/api/reports/${r.id}/status`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: select.value }),
      });
      toast(`${label(r)} → ${select.value}`);
      refreshStats();
    } catch (err) {
      toast(err.message, 'err');
      select.value = r.status;
    } finally {
      select.disabled = false;
    }
  });
  return select;
}

function renderTable(reports) {
  const rows = [...reports].sort((a, b) =>
    (STATUS_ORDER[a.status] ?? 9) - (STATUS_ORDER[b.status] ?? 9) ||
    (b.severity || 0) - (a.severity || 0) ||
    Date.parse(b.created_at) - Date.parse(a.created_at),
  );
  document.querySelector('#reportTable tbody').replaceChildren(...rows.map((r) =>
    el('tr', {},
      el('td', {}, el('img', { src: r.photo, alt: '', loading: 'lazy' })),
      el('td', {},
        el('strong', {}, label(r)),
        el('div', { style: 'font-size:11.5px;color:var(--ink-3)' },
          r.kind === 'feature' ? 'accessible feature' : 'barrier',
          r.reporter ? ` · by ${r.reporter}` : ''),
      ),
      el('td', { class: 'hide-sm', style: 'max-width:230px' }, shortAddress(r)),
      el('td', {}, sevTag(r)),
      el('td', {}, statusSelect(r)),
      el('td', { class: 'hide-sm num' }, String(r.confirmations)),
      el('td', { class: 'hide-sm num' }, `${daysAgo(r.created_at)}d`),
      el('td', {}, r.letter ? el('a', { href: `/#r=${r.id}` }, 'View') : '—'),
    ),
  ));
}

async function refreshStats() {
  renderTiles(await api('/api/stats'));
}

async function init() {
  meta = await api('/api/meta');
  const [stats, { reports }] = await Promise.all([api('/api/stats'), api('/api/reports')]);
  renderTiles(stats);
  renderBars(stats);
  renderTable(reports);
}

init().catch((err) => toast(`Failed to load: ${err.message}`, 'err'));
