import test from 'node:test';
import assert from 'node:assert/strict';
import { findDuplicateUnitIdentifier, matchesShowroomUnit, normalizeUnitIdentifier } from '../src/showroom-units.js';

const units = [
  { id: 'u1', vin: 'ABC-123', engine_number: 'ENG 55', barcode: 'UNIT-001', unit_year: 2025, unit_color: 'أحمر', supplier_name: 'مؤسسة النور', supplier_bill_number: 'INV-77', unit_status: 'available', motorcycles: { name: 'هوندا CB', model_year: 2025 } },
  { id: 'u2', vin: 'XYZ-987', engine_number: 'ENG-77', unit_status: 'sold', motorcycles: { name: 'Yamaha MT', model_year: 2024 } }
];

test('identifier normalization ignores punctuation and letter case', () => {
  assert.equal(normalizeUnitIdentifier(' ab-c 123 '), 'ABC123');
});

test('showroom search matches VIN, engine, model and status filters', () => {
  assert.equal(matchesShowroomUnit(units[0], 'abc 123'), true);
  assert.equal(matchesShowroomUnit(units[0], 'eng-55'), true);
  assert.equal(matchesShowroomUnit(units[1], 'Yamaha MT'), true);
  assert.equal(matchesShowroomUnit(units[0], 'هوندا'), true);
  assert.equal(matchesShowroomUnit(units[0], 'أحمر'), true);
  assert.equal(matchesShowroomUnit(units[0], '2025'), true);
  assert.equal(matchesShowroomUnit(units[0], 'UNIT-001'), true);
  assert.equal(matchesShowroomUnit(units[0], 'مؤسسة النور'), true);
  assert.equal(matchesShowroomUnit(units[0], 'INV-77'), true);
  assert.equal(matchesShowroomUnit(units[0], 'هوندا', 'sold'), false);
  assert.equal(matchesShowroomUnit(units[1], '', 'sold'), true);
});

test('search normalization handles Arabic punctuation and empty input', () => {
  assert.equal(matchesShowroomUnit(units[0], ''), true);
  assert.equal(matchesShowroomUnit(units[0], 'غير موجود'), false);
  assert.equal(matchesShowroomUnit(units[0], 'CB'), true);
});

test('duplicate guard catches normalized collisions but allows current record', () => {
  assert.equal(findDuplicateUnitIdentifier(units, 'vin', 'abc123')?.id, 'u1');
  assert.equal(findDuplicateUnitIdentifier(units, 'engine_number', 'eng 77')?.id, 'u2');
  assert.equal(findDuplicateUnitIdentifier(units, 'vin', 'abc123', 'u1'), null);
  assert.equal(findDuplicateUnitIdentifier(units, 'vin', 'new-456'), null);
  assert.equal(findDuplicateUnitIdentifier(units, 'vin', ''), null);
});


test('showroom filters combine model, sale-price range, and inclusive receipt-date bounds', () => {
  const received = { ...units[0], motorcycle_id: 'model-a', received_at: '2026-11-12T14:30:00Z', motorcycles: { ...units[0].motorcycles, price: 125000 } };
  const otherModel = { ...units[1], motorcycle_id: 'model-b', received_at: '2026-11-13T00:00:00Z', motorcycles: { ...units[1].motorcycles, price: 180000 } };
  assert.equal(matchesShowroomUnit(received, '', 'all', { modelId: 'model-a', minPrice: '120000', maxPrice: '125000', receivedFrom: '2026-11-12', receivedTo: '2026-11-12' }), true);
  assert.equal(matchesShowroomUnit(received, '', 'all', { modelId: 'model-b' }), false);
  assert.equal(matchesShowroomUnit(received, '', 'all', { minPrice: '125001' }), false);
  assert.equal(matchesShowroomUnit(received, '', 'all', { maxPrice: '124999' }), false);
  assert.equal(matchesShowroomUnit(received, '', 'all', { receivedFrom: '2026-11-13' }), false);
  assert.equal(matchesShowroomUnit(received, '', 'all', { receivedTo: '2026-11-11' }), false);
  assert.equal(matchesShowroomUnit(otherModel, '', 'all', { receivedFrom: '2026-11-12', receivedTo: '2026-11-13' }), true);
});

test('date filters exclude units with no recorded receipt date rather than guessing from registration', () => {
  assert.equal(matchesShowroomUnit(units[0], '', 'all', { receivedFrom: '2026-01-01' }), false);
  assert.equal(matchesShowroomUnit(units[0], '', 'all', { receivedTo: '2026-12-31' }), false);
});
