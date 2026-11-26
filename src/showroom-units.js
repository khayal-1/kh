/** Search and duplicate guards for already-loaded physical showroom units. */
export function normalizeUnitIdentifier(value) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export function normalizeShowroomSearch(value) {
  return String(value || '').toLocaleLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

export function matchesShowroomUnit(unit, query, status = 'all') {
  if (status !== 'all' && unit?.unit_status !== status) return false;
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

export function findDuplicateUnitIdentifier(units, field, value, exceptId = null) {
  const normalized = normalizeUnitIdentifier(value);
  if (!normalized) return null;
  return (units || []).find(unit => unit?.id !== exceptId && normalizeUnitIdentifier(unit?.[field]) === normalized) || null;
}
