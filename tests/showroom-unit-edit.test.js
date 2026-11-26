import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(new URL('../supabase/migrations/20261126154000_edit_physical_unit_year_color.sql', import.meta.url), 'utf8');
const app = await readFile(new URL('../app.js', import.meta.url), 'utf8');
const legacy = await readFile(new URL('../supabase/migrations/20261123141902_improve_showroom_store_unit_management.sql', import.meta.url), 'utf8');

test('unit edit form offers per-unit year/color and saves through the additive RPC', () => {
  assert.match(app, /name="unit_year" type="number" inputmode="numeric" min="1900" max="2200"/);
  assert.match(app, /name="unit_color" maxlength="60"/);
  assert.match(app, /update_motorcycle_unit_details_with_attributes/);
  assert.match(app, /p_unit_year:yearValue\?Number\(yearValue\):null/);
  assert.match(app, /p_unit_color:safeName\(fd\.get\('unit_color'\)\)\|\|null/);
});

test('new unit-edit RPC changes only unit attributes while preserving permission and stock safeguards', () => {
  assert.match(migration, /auth\.uid\(\).*?private\.can_manage_finance\(\).*?catalog_manage/s);
  assert.match(migration, /set unit_year=p_unit_year/);
  assert.match(migration, /unit_color=nullif\(btrim\(coalesce\(p_unit_color,''\)\),''\)/);
  assert.match(migration, /where id=p_unit_id/);
  assert.match(migration, /v_unit\.sale_item_id is not null and p_unit_status<>'sold'/);
  assert.match(migration, /set stock=v_stock/);
  assert.match(migration, /grant execute on function public\.update_motorcycle_unit_details_with_attributes/);
  assert.match(legacy, /create or replace function private\.update_motorcycle_unit_details\(/);
  assert.match(migration, /does not|preserve the existing/i);
  assert.doesNotMatch(migration, /update public\.motorcycles\s+set model_year/);
});
