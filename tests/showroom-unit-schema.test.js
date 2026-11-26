import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(new URL('../supabase/migrations/20261126150000_add_physical_unit_year_color.sql', import.meta.url), 'utf8');
const app = await readFile(new URL('../app.js', import.meta.url), 'utf8');

test('physical unit migration adds optional year and color without touching model fields', () => {
  assert.match(migration, /add column if not exists unit_year smallint/i);
  assert.match(migration, /add column if not exists unit_color text/i);
  assert.match(migration, /unit_year is null or unit_year between 1900 and 2200/i);
  assert.doesNotMatch(migration, /drop column|delete from public\.(motorcycles|motorcycle_units)/i);
});

test('atomic receiving RPC stores per-unit year and color', () => {
  assert.match(migration, /private\.receive_supplier_purchase_order_units_impl\(/i);
  assert.match(migration, /unit_year,unit_color/i);
  assert.match(migration, /nullif\(unit->>'unit_year',''\)::smallint/i);
  assert.match(migration, /unit->>'unit_color'/i);
  assert.match(app, /name="unit_year" type="number"/);
  assert.match(app, /name="unit_color" maxlength="60"/);
  assert.match(app, /unit_year:value\('unit_year'\)\?Number\(value\('unit_year'\)\):null/);
  assert.match(app, /unit_color:safeName\(value\('unit_color'\)\)\|\|null/);
});

test('unit photos use a private bucket and a separate metadata table', async () => {
  const photosMigration = await readFile(new URL('../supabase/migrations/20261126153000_unit_photo_storage.sql', import.meta.url), 'utf8');
  assert.match(photosMigration, /'motorcycle-unit-photos','motorcycle-unit-photos',false,8388608/i);
  assert.match(photosMigration, /create table if not exists public\.motorcycle_unit_photos/i);
  assert.match(photosMigration, /references public\.motorcycle_units\(id\) on delete restrict/i);
  assert.match(photosMigration, /unique index if not exists motorcycle_unit_photos_one_primary_uidx/i);
  assert.match(photosMigration, /create policy motorcycle_unit_photo_objects_insert/i);
  assert.match(photosMigration, /has_employee_permission\('catalog_manage'\)/i);
  assert.doesNotMatch(photosMigration, /drop policy.*catalog_images|update public\.photo_assets|delete from public\.photo_assets/i);
  assert.match(app, /storage\.from\('motorcycle-unit-photos'\)\.upload/i);
  assert.match(app, /optimizeCatalogImage\(original\)/i);
  assert.match(app, /createSignedUrl\(photo\.storage_path,3600\)/i);
  assert.match(app, /data-unit-photo-primary/i);
});


test('receiving starts with one visible unit and expands unit entry progressively', () => {
  assert.ok(app.includes('inputmode="numeric" min="0" max="${remaining}" value="1"'));
  assert.ok(app.includes('<details class="panel receive-unit-step" data-unit-row'));
  assert.ok(app.includes("updateReceiveUnitVisibility(e.target.closest('form'))"));
  assert.match(app, /autoBarcodeFromVin\(vin\)/);
  assert.ok(app.includes('بعد التسجيل أضف الصور والمستندات من تفاصيل الوحدة'));
});
