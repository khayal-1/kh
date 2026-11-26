export const MOTORCYCLE_DOCUMENT_MAX_BYTES = 15 * 1024 * 1024;

const MIME_EXTENSIONS = Object.freeze({
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp'
});

export function motorcycleDocumentExtension(mimeType) {
  return MIME_EXTENSIONS[String(mimeType || '').toLowerCase()] || null;
}

export function validateMotorcycleDocument(file) {
  if (!file || typeof file !== 'object') return 'الملف غير صالح';
  if (!motorcycleDocumentExtension(file.type)) return 'الملفات المسموحة: PDF أو JPG أو PNG أو WebP';
  if (!Number.isFinite(file.size) || file.size < 1 || file.size > MOTORCYCLE_DOCUMENT_MAX_BYTES) return 'يجب ألا يتجاوز حجم الملف 15 ميجابايت';
  return null;
}

export function motorcycleDocumentPath(targetType, targetId, documentId, mimeType) {
  const folder = targetType === 'unit' ? 'units' : targetType === 'supplier_bill' ? 'supplier-bills' : null;
  const extension = motorcycleDocumentExtension(mimeType);
  if (!folder || !targetId || !documentId || !extension) return null;
  return `${folder}/${targetId}/${documentId}.${extension}`;
}

export function cleanMotorcycleDocumentName(name) {
  return String(name || '').replace(/[\\/\u0000-\u001f\u007f]/g, '_').trim().slice(0, 180) || 'مستند';
}

export function canDeleteMotorcycleDocument(document, userId) {
  return Boolean(document && userId && document.created_by === userId);
}
