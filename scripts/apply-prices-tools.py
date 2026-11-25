#!/usr/bin/env python3
from pathlib import Path

APP = Path("app.js")
text = APP.read_text(encoding="utf-8")
if "function getMarketPrices()" in text and "bulkPriceForm" in text:
    print("already applied")
    raise SystemExit(0)

HELPERS = """
function getMarketPrices() {
  try { return JSON.parse(localStorage.getItem('kh_market_prices') || '{}') || {}; } catch { return {}; }
}
function setMarketPrice(bikeId, price) {
  const map = getMarketPrices();
  if (price === '' || price == null || Number.isNaN(Number(price))) delete map[bikeId];
  else map[bikeId] = Number(price);
  localStorage.setItem('kh_market_prices', JSON.stringify(map));
}
function autoBarcodeFromVin(vin) {
  const v = String(vin || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  if (v.length >= 8) return 'BC-' + v.slice(-10);
  return 'BC-' + Date.now().toString(36).toUpperCase();
}
"""

if "function getMarketPrices()" not in text:
    text = text.replace("function pageInventory() {", HELPERS + "\nfunction pageInventory() {", 1)

old = "const costMap = new Map((state.inventoryCosts || []).map((x) => [x.motorcycle_id, x]));"
new = old + "\n  const marketMap = getMarketPrices();"
if "const marketMap = getMarketPrices()" not in text:
    text = text.replace(old, new, 1)

old = "    const sell = Number(b.price || 0);\n    const margin = sell - unitCost;"
new = "    const sell = Number(b.price || 0);\n    const market = Number(marketMap[b.id] || 0);\n    const margin = sell - unitCost;\n    const vsMarket = market > 0 ? sell - market : null;"
if "const market = Number(marketMap" not in text:
    text = text.replace(old, new, 1)

old_th = "<th>سعر البيع</th><th>هامش الربح</th>"
new_th = "<th>سعر البيع</th><th>سعر السوق</th><th>مقارنة السوق</th><th>هامش الربح</th>"
pi = text.index("function pageInventory()")
pd = text.index("function pageDashboard()")
if old_th in text[pi:pd]:
    text = text[:pi] + text[pi:pd].replace(old_th, new_th, 1) + text[pd:]

old_row = "<td>${priceCell}</td>\n      <td>${unitCost ? money(margin)"
new_row = """<td>${priceCell}</td>
      <td>${canEditPrice
      ? `<form id=\"marketPriceForm\" class=\"inline-form\" data-bike-id=\"${esc(b.id)}\">
           <input type=\"number\" name=\"market_price\" min=\"0\" step=\"0.01\" value=\"${market || ''}\" placeholder=\"—\" style=\"max-width:110px\">
           <button class=\"btn btn-outline btn-sm\" type=\"submit\">حفظ</button>
         </form>`
      : (market ? money(market) : '<span class=\"hint\">—</span>')}</td>
      <td>${vsMarket == null ? '—' : (vsMarket === 0 ? 'مساوٍ للسوق' : (vsMarket > 0 ? ('أعلى ' + money(vsMarket)) : ('أقل ' + money(Math.abs(vsMarket)))))}</td>
      <td>${unitCost ? money(margin)"""
if old_row in text:
    text = text.replace(old_row, new_row, 1)

text = text.replace('colspan="8">لا توجد أصناف', 'colspan="9">لا توجد أصناف')

old_bc = "p_barcode:safeName(fd.get('barcode'))||null,"
new_bc = "p_barcode:safeName(fd.get('barcode'))||autoBarcodeFromVin(fd.get('vin')),"
if old_bc in text and "autoBarcodeFromVin(fd.get" not in text:
    text = text.replace(old_bc, new_bc, 1)

old_hint = '<div class="field"><label>الباركود</label><input name="barcode" maxlength="80"></div>'
new_hint = '<div class="field"><label>الباركود (يُولَّد تلقائياً من الشاسيه إن تُرك فارغاً)</label><input name="barcode" maxlength="80" placeholder="اختياري — توليد تلقائي"></div>'
if old_hint in text:
    text = text.replace(old_hint, new_hint)

text = text.replace("طرازات مسّل*", "طرازات مسجّلة")

HANDLERS = """
  if (form.id === 'marketPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية تعديل سعر السوق','error'); return; }
    const fd = new FormData(form);
    const bikeId = form.dataset.bikeId;
    setMarketPrice(bikeId, fd.get('market_price') === '' ? null : Number(fd.get('market_price')));
    render();
    toast('تم حفظ سعر السوق','success');
    return;
  }
  if (form.id === 'bulkPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية التعديل الجماعي','error'); return; }
    if (!supabase) { toast('الاتصال غير متاح','error'); return; }
    const fd = new FormData(form);
    const mode = fd.get('mode');
    const value = Number(fd.get('value'));
    if (!(value >= 0)) { toast('أدخل قيمة صحيحة','error'); return; }
    const selected = Array.from(form.querySelectorAll('select[name="bike_ids"] option:checked')).map((o) => o.value);
    let bikes = (get(DB.BIKES) || []).filter((b) => !b.is_demo);
    if (selected.length) bikes = bikes.filter((b) => selected.includes(b.id));
    if (!bikes.length) { toast('لا توجد طرازات للتعديل','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    let ok = 0, fail = 0;
    for (const b of bikes) {
      let price = Number(b.price || 0);
      if (mode === 'set') price = value;
      else if (mode === 'percent_up') price = price * (1 + value / 100);
      else if (mode === 'percent_down') price = price * (1 - value / 100);
      else if (mode === 'amount_up') price = price + value;
      else if (mode === 'amount_down') price = Math.max(0, price - value);
      price = Math.round(price * 100) / 100;
      const { error } = await supabase.from('motorcycles').update({ price }).eq('id', b.id);
      if (error) fail += 1; else ok += 1;
    }
    if (btn) btn.disabled = false;
    await Promise.all([loadMotorcycles(), loadInventoryData()]);
    render();
    toast('تم تحديث ' + ok + ' طرازاً' + (fail ? (' — فشل ' + fail) : ''), fail ? 'error' : 'success');
    return;
  }
"""

if "form.id === 'bulkPriceForm'" not in text:
    end_sell = text.index("  if (form.id === 'inventoryCostForm') {")
    text = text[:end_sell] + HANDLERS + text[end_sell:]

bulk_panel = """
    ${canEditPrice ? `<div class=\"panel\">
      <div class=\"panel-title\"><i class=\"fa-solid fa-layer-group\"></i> تعديل جماعي لأسعار البيع</div>
      <form id=\"bulkPriceForm\" class=\"form-grid\">
        <div class=\"form-row\">
          <div class=\"field\">
            <label>الطرازات (فارغ = الكل)</label>
            <select name=\"bike_ids\" multiple size=\"4\" style=\"min-height:90px\">${bikes.map((b)=>'<option value="'+esc(b.id)+'">'+esc(b.name)+' — '+money(b.price||0)+'</option>').join('')}</select>
          </div>
          <div class=\"field\">
            <label>طريقة التعديل</label>
            <select name=\"mode\" required>
              <option value=\"set\">تعيين سعر ثابت</option>
              <option value=\"percent_up\">زيادة %</option>
              <option value=\"percent_down\">تخفيض %</option>
              <option value=\"amount_up\">زيادة بمبلغ</option>
              <option value=\"amount_down\">تخفيض بمبلغ</option>
            </select>
            <label class=\"mt-2\">القيمة</label>
            <input type=\"number\" name=\"value\" min=\"0\" step=\"0.01\" required>
          </div>
        </div>
        <button class=\"btn btn-primary\" type=\"submit\"><i class=\"fa-solid fa-floppy-disk\"></i> تطبيق التعديل الجماعي</button>
      </form>
      <p class=\"hint mt-2\">سعر السوق يُحفظ على هذا الجهاز لمتابعة المنافسة. الباركود يُولَّد تلقائياً عند تسجيل وحدة بلا باركود.</p>
    </div>` : ''}

    <div class=\"panel printable-panel\">
"""

pi = text.index("function pageInventory()")
pd = text.index("function pageDashboard()")
section = text[pi:pd]
marker = '    <div class="panel printable-panel">'
if "id=\"bulkPriceForm\"" not in section and marker in section:
    abs_idx = pi + section.index(marker)
    text = text[:abs_idx] + bulk_panel + text[abs_idx + len(marker):]

APP.write_text(text, encoding="utf-8")
print("applied", APP.stat().st_size)
