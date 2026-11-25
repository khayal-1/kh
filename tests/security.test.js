import test from 'node:test';
import assert from 'node:assert/strict';
import { esc, safeImageUrl } from '../src/security.js';

test('esc encodes all HTML-sensitive characters', () => {
  assert.equal(esc(String.fromCharCode(60, 38, 62, 34, 39)), '&lt;&amp;&gt;&quot;&#39;');
});

test('esc handles nullish values without throwing', () => {
  assert.equal(esc(null), '');
  assert.equal(esc(undefined), '');
});

test('safeImageUrl accepts HTTPS, HTTP and relative image paths', () => {
  assert.equal(safeImageUrl('https://cdn.example.com/photo.jpg'), 'https://cdn.example.com/photo.jpg');
  assert.equal(safeImageUrl('http://localhost:5173/photo.jpg'), 'http://localhost:5173/photo.jpg');
  assert.equal(safeImageUrl('/branding/photo.jpg'), '/branding/photo.jpg');
});

test('safeImageUrl rejects executable and unsupported URL schemes', () => {
  assert.equal(safeImageUrl('javascript:alert(1)'), '');
  assert.equal(safeImageUrl('data:image/svg+xml,<svg onload=alert(1)>'), '');
  assert.equal(safeImageUrl('file:///etc/passwd'), '');
  assert.equal(safeImageUrl(''), '');
});
