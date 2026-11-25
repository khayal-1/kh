/**
 * Market analysis (PriceBuddy) — staff catalog tool.
 * UI helpers used by pageMarketAnalysis in app.js.
 */

export function fmtMarketPrice(n) {
  if (n == null || Number.isNaN(Number(n))) return '—';
  return Number(n).toLocaleString('ar-EG') + ' ج.م';
}

export function sparklineSvg(data, w = 90, h = 26) {
  const nums = (data || []).map(Number).filter((n) => Number.isFinite(n));
  if (nums.length < 2) return '<span class="mk-muted">بيانات غير كافية</span>';
  const min = Math.min(...nums);
  const max = Math.max(...nums);
  const r = max - min || 1;
  const pts = nums
    .map((v, i) => `${(i / (nums.length - 1)) * w},${h - ((v - min) / r) * (h - 4) - 2}`)
    .join(' ');
  const up = nums[nums.length - 1] >= nums[0];
  const stroke = up ? 'var(--mk-up, #1a8f4c)' : 'var(--mk-down, #c43d3d)';
  return `<svg width="${w}" height="${h}" aria-hidden="true"><polyline points="${pts}" fill="none" stroke="${stroke}" stroke-width="1.8" /></svg>`;
}

export function changeHtml(v) {
  if (v == null || Math.abs(Number(v)) < 0.1) return '<span class="mk-muted">—</span>';
  const n = Number(v);
  const cls = n > 0 ? 'mk-up' : 'mk-down';
  const arrow = n > 0 ? '↑' : '↓';
  return `<span class="${cls}">${arrow} ${Math.abs(n).toFixed(1)}%</span>`;
}

export function filterMarketRows(rows, q, filter) {
  const query = String(q || '').trim().toLowerCase();
  return (rows || []).filter((r) => {
    if (filter && filter !== 'all' && r.category !== filter) return false;
    if (!query) return true;
    return String(r.title || '').toLowerCase().includes(query);
  });
}
