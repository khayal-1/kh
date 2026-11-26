/** Search and duplicate guards for already-loaded physical showroom units. */
export function normalizeUnitIdentifier(value) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export function normalizeShowroomSearch(value) {
  return String(value || '').toLocaleLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

export function matchesShowroomUnit(unit, query, status = 'all', filters = {}) {
  if (status !== 'all' && unit?.unit_status !== status) return false;
  const modelId = String(filters.modelId || 'all');
  if (modelId !== 'all' && String(unit?.motorcycle_id || unit?.motorcycles?.id || '') !== modelId) return false;

  const rawPrice = unit?.sale_price ?? unit?.motorcycles?.price;
  const price = rawPrice === '' || rawPrice == null ? Number.NaN : Number(rawPrice);
  const minPrice = filters.minPrice === '' || filters.minPrice == null ? null : Number(filters.minPrice);
  const maxPrice = filters.maxPrice === '' || filters.maxPrice == null ? null : Number(filters.maxPrice);
  if (minPrice != null && (!Number.isFinite(price) || price < minPrice)) return false;
  if (maxPrice != null && (!Number.isFinite(price) || price > maxPrice)) return false;

  const receivedDate = unit?.received_at ? new Date(unit.received_at) : null;
  const receivedAt = receivedDate && !Number.isNaN(receivedDate.getTime())
    ? `${receivedDate.getFullYear()}-${String(receivedDate.getMonth() + 1).padStart(2, '0')}-${String(receivedDate.getDate()).padStart(2, '0')}`
    : '';
  if (filters.receivedFrom && (!receivedAt || receivedAt < filters.receivedFrom)) return false;
  if (filters.receivedTo && (!receivedAt || receivedAt > filters.receivedTo)) return false;

  const needle = normalizeShowroomSearch(query);
  if (!needle) return true;
  const model = unit?.motorcycles || {};
  const haystack = [
    unit?.vin, unit?.engine_number, unit?.barcode, unit?.unit_status, unit?.unit_year, unit?.unit_color,
    unit?.unit_code, unit?.supplier_bill_number, unit?.supplier_name, unit?.receipt_number,
    model?.name, model?.model_year, model?.category,
  ].map(normalizeShowroomSearch).join(' ');
  return haystack.includes(needle);
}

export function validateShowroomUnitIntake(values = {}) {
  const year = values.unit_year == null || values.unit_year === '' ? null : Number(values.unit_year);
  if (year !== null && (!Number.isInteger(year) || year < 1900 || year > 2200)) return 'year';
  if (String(values.unit_color || '').trim().length > 60) return 'color';
  const start = String(values.warranty_start || '');
  const end = String(values.warranty_end || '');
  if (start && end && end < start) return 'warranty';
  return null;
}

export function findDuplicateUnitIdentifier(units, field, value, exceptId = null) {
  const normalized = normalizeUnitIdentifier(value);
  if (!normalized) return null;
  return (units || []).find(unit => unit?.id !== exceptId && normalizeUnitIdentifier(unit?.[field]) === normalized) || null;
}
