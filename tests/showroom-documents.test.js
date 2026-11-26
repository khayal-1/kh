import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanMotorcycleDocumentName, motorcycleDocumentExtension, motorcycleDocumentPath, validateMotorcycleDocument, MOTORCYCLE_DOCUMENT_MAX_BYTES } from '../src/showroom-documents.js';

test('document types and path are constrained to the two supported target types', () => {
  assert.equal(motorcycleDocumentExtension('application/pdf'), 'pdf');
  assert.equal(motorcycleDocumentExtension('image/jpeg'), 'jpg');
  assert.equal(motorcycleDocumentExtension('text/html'), null);
  assert.equal(motorcycleDocumentPath('unit', 'u1', 'd1', 'image/png'), 'units/u1/d1.png');
  assert.equal(motorcycleDocumentPath('supplier_bill', 'b1', 'd2', 'application/pdf'), 'supplier-bills/b1/d2.pdf');
  assert.equal(motorcycleDocumentPath('other', 'x', 'd3', 'application/pdf'), null);
});

test('documents reject unsupported types, empty files and files over the bucket limit', () => {
  assert.equal(validateMotorcycleDocument({type:'application/pdf',size:1}), null);
  assert.match(validateMotorcycleDocument({type:'text/plain',size:1}), /المسموحة/);
  assert.match(validateMotorcycleDocument({type:'image/png',size:0}), /15 ميجابايت/);
  assert.match(validateMotorcycleDocument({type:'image/jpeg',size:MOTORCYCLE_DOCUMENT_MAX_BYTES+1}), /15 ميجابايت/);
});

test('display filename cannot create a path or inject control characters', () => {
  assert.equal(cleanMotorcycleDocumentName('../invoice\n.pdf'), '.._invoice_.pdf');
});

test('document deletion is exposed only to the uploader, matching metadata and Storage RLS', async () => {
  const { canDeleteMotorcycleDocument } = await import('../src/showroom-documents.js');
  assert.equal(canDeleteMotorcycleDocument({created_by:'user-1'}, 'user-1'), true);
  assert.equal(canDeleteMotorcycleDocument({created_by:'user-1'}, 'user-2'), false);
  assert.equal(canDeleteMotorcycleDocument({created_by:null}, 'user-1'), false);
});
