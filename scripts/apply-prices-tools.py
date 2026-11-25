#!/usr/bin/env python3
from pathlib import Path
import base64
APP = Path("app.js")
text = APP.read_text(encoding="utf-8")
if "sellPriceForm" in text and "\u0633\u0639\u0631 \u0627\u0644\u0634\u0631\u0627\u0621 (\u0627\u0644\u062a\u0643\u0644\u0641\u0629)" in text:
    print("already applied")
    raise SystemExit(0)
# Load NEW pageInventory from sibling b64 file if present, else embed minimal
b64_path = Path("scripts/pageInventory.b64")
if not b64_path.exists():
    raise SystemExit("missing scripts/pageInventory.b64")
NEW = base64.b64decode(b64_path.read_text(encoding="ascii").strip()).decode("utf-8")
start = text.index("function pageInventory() {")
end = text.index("function pageDashboard() {")
text = text[:start] + NEW + text[end:]
needle = "if (route === 'manage-bikes' && state.user) Promise.all([loadMotorcycles(),loadMotorcycleUnits()]).then(render);"
if "route === 'inventory' && state.user" not in text:
    if needle not in text:
        raise SystemExit("navigate needle missing")
    text = text.replace(needle, needle + "\n  if (route === 'inventory' && state.user) Promise.all([loadMotorcycles(),loadInventoryData()]).then(render);", 1)
old_cost = "  if (form.id === 'inventoryCostForm') {"
if "form.id === 'sellPriceForm'" not in text:
    if old_cost not in text:
        raise SystemExit("inventoryCostForm missing")
    sell = """  if (form.id === 'sellPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية تعديل سعر البيع','error'); return; }
    if (!supabase) { toast('الاتصال غير متاح','error'); return; }
    const fd = new FormData(form);
    const bikeId = form.dataset.bikeId;
    const price = Number(fd.get('price'));
    if (!bikeId || !(price >= 0)) { toast('أدخل سعراً صحيحاً','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    const { error } = await supabase.from('motorcycles').update({ price }).eq('id', bikeId);
    if (btn) btn.disabled = false;
    if (error) { toast(error.message || 'تعذر حفظ سعر البيع','error'); return; }
    await Promise.all([loadMotorcycles(), loadInventoryData()]);
    render();
    toast('تم تحديث سعر البيع','success');
    return;
  }
"""
    text = text.replace(old_cost, sell + old_cost, 1)
text = text.replace(
    '<p class="page-sub">بيع مباشر من المعرض — لا يحتاج العميل إلى حساب دخول</p>',
    '<p class="page-sub">نظام البيع داخل المعرض مع دعم الماسح الضوئي (شاسيه/باركود). عند إتمام البيع تُسجَّل الفاتورة وتُخرج الوحدة من العرض تلقائياً مع الإبقاء على بيانات البيع.</p>',
    1,
)
old_mb = '<h2 class="page-title"><i class="fa-solid fa-motorcycle"></i> المعرض / الكتالوج</h2>'
if old_mb in text and "مرجع الأصناف بتفاصيل كاملة" not in text:
    text = text.replace(
        old_mb,
        old_mb + "\n    <p class=\"page-sub\">مرجع الأصناف بتفاصيل كاملة (موديل، فئة، وصف، صور). أضف صنفاً أو وحدة برقم شاسيه/باركود؛ استخدم حالة العرض للنشر في المتجر أو الإبقاء كمسودة. عند البيع تُخرج الوحدة من العرض تلقائياً مع الإبقاء على الفاتورة وبيانات البيع.</p>",
        1,
    )
APP.write_text(text, encoding="utf-8")
print("applied", APP.stat().st_size)
