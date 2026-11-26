import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/migrations/20261126155000_motorcycle_documents.sql', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

test('documents are additive, private and limited to unit or supplier-bill targets', () => {
  assert.match(sql, /values \('motorcycle-documents','motorcycle-documents',false,15728640/);
  assert.match(sql, /target_type in \('unit','supplier_bill'\)/);
  assert.match(sql, /motorcycle_documents_one_target check/);
  assert.match(sql, /references public\.motorcycle_units\(id\) on delete restrict/);
  assert.match(sql, /references public\.supplier_bills\(id\) on delete restrict/);
  assert.match(sql, /revoke all on public\.motorcycle_documents from public,anon,authenticated/);
});

test('document metadata and Storage policies enforce role and object-path association', () => {
  assert.match(sql, /private\.can_access_motorcycle_document_target\(target_type,coalesce\(motorcycle_unit_id,supplier_bill_id\),true\)/);
  assert.match(sql, /private\.can_access_motorcycle_document_target\(d\.target_type,coalesce\(d\.motorcycle_unit_id,d\.supplier_bill_id\),false\)/);
  assert.match(sql, /private\.can_access_motorcycle_document_target\(d\.target_type,coalesce\(d\.motorcycle_unit_id,d\.supplier_bill_id\),true\)/);
  assert.match(sql, /d\.storage_path=name/);
  assert.match(sql, /d\.created_by=\(select auth\.uid\(\)\)/);
});

test('app exposes private attachments for unit details and supplier invoices', () => {
  assert.match(app, /data-supplier-bill-docs/);
  assert.match(app, /name="bill_documents" type="file"/);
  assert.match(app, /name="unit_documents" type="file"/);
  assert.match(app, /createSignedUrl\(doc\.storage_path,3600\)/);
  assert.match(app, /uploadMotorcycleDocuments\('supplier_bill'/);
});

test('supplier UI honors the same purchase-management permission as its RPC and RLS', () => {
  assert.match(app, /function canManagePurchasing\(\) \{ return hasRole\('admin','manager','owner'\) \|\| hasPermission\('purchasing_manage'\); \}/);
  assert.match(app, /function pageSuppliers\(\) \{\s*if \(!canManagePurchasing\(\)\)/);
  assert.match(app, /if\(!canManagePurchasing\(\)\|\|!supabase\).*صلاحية إدارة فواتير الموردين/);
  assert.match(sql, /return public\.can_manage_purchasing\(\);/);
});

test('only document creators see delete controls, matching the created_by RLS predicate', () => {
  assert.match(app, /created_by,created_at/);
  assert.match(app, /canDeleteMotorcycleDocument\(doc,state\.user\?\.id\)/);
  assert.match(sql, /created_by=\(select auth\.uid\(\)\)/);
});

test('supplier invoice RPC binds received units once and serializes concurrent billing', () => {
  const workflow = readFileSync(new URL('../supabase/migrations/20261123062000_supplier_bill_line_items_and_unit_matching.sql', import.meta.url), 'utf8');
  assert.match(workflow, /motorcycle_unit_id uuid not null unique references public\.motorcycle_units\(id\)/);
  assert.match(workflow, /purchase_orders po[\s\S]*for update/);
  assert.match(workflow, /for update of pru skip locked/);
  assert.match(workflow, /insert into public\.supplier_bill_item_units\(supplier_bill_item_id,motorcycle_unit_id\)/);
  assert.match(workflow, /round\(v_total,2\)<>round\(p_total_amount,2\)/);
  assert.match(app, /supabase\.rpc\('create_supplier_bill'/);
  assert.match(app, /purchase_receipt_item_id:row\.dataset\.receiptItemId/);
});


test('showroom loads supplier invoice references only for purchasing-authorized staff', () => {
  assert.match(app, /async function loadShowroomSupplierRefs\(\)[\s\S]*?if \(!supabase \|\| !canManagePurchasing\(\)\) return/);
  assert.ok(app.includes("supplier_bill_items!inner(supplier_bill_id,supplier_bills!inner(bill_number,suppliers!inner(name)))"));
  assert.ok(app.includes("purchase_receipt_items!inner(purchase_receipts!inner(receipt_number,received_at))"));
  assert.match(app, /purchaseRef\.supplier_bill_number/);
  assert.match(app, /received_at:receipt\.received_at/);
});
