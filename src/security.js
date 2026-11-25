export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  })[character]);
}

/**
 * Allow only browser-safe HTTP(S) and relative image URLs in HTML attributes.
 * Reject javascript:, data:, file:, and other unsupported URL schemes.
 */
export function safeImageUrl(value) {
  const candidate = String(value ?? '').trim();
  if (!candidate) return '';
  try {
    const parsed = new URL(candidate, 'https://elkhayal.invalid');
    if (!['http:', 'https:'].includes(parsed.protocol)) return '';
    if (parsed.username || parsed.password) return '';
    return candidate;
  } catch {
    return '';
  }
}
