import test from 'node:test';
import assert from 'node:assert/strict';
import { applyQueryResults } from '../src/purchasing-results.js';

test('successful supplier query is retained when a sibling purchasing query fails', () => {
  const state = { suppliers: [{ id: 'old' }], supplierBills: [{ id: 'previous' }] };
  const errors = [];
  const loaded = applyQueryResults(state, [
    { key: 'suppliers', label: 'الموردين', result: { data: [{ id: 'supplier-1' }], error: null } },
    { key: 'supplierBills', label: 'فواتير الموردين', result: { data: null, error: new Error('unavailable') } }
  ], (label, error) => errors.push({ label, error }));

  assert.deepEqual(state.suppliers, [{ id: 'supplier-1' }]);
  assert.deepEqual(state.supplierBills, [{ id: 'previous' }]);
  assert.equal(loaded.has('suppliers'), true);
  assert.equal(loaded.has('supplierBills'), false);
  assert.equal(errors.length, 1);
  assert.equal(errors[0].label, 'فواتير الموردين');
});

test('empty successful result clears only its own collection', () => {
  const state = { suppliers: [{ id: 'supplier-1' }], purchaseOrders: [{ id: 'order-1' }] };
  const loaded = applyQueryResults(state, [
    { key: 'suppliers', label: 'الموردين', result: { data: [], error: null } }
  ]);

  assert.deepEqual(state.suppliers, []);
  assert.deepEqual(state.purchaseOrders, [{ id: 'order-1' }]);
  assert.equal(loaded.has('suppliers'), true);
});
