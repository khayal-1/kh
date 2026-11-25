#!/usr/bin/env python3
from pathlib import Path
import base64

APP = Path("app.js")
text = APP.read_text(encoding="utf-8")
if "sellPriceForm" in text and "\u0633\u0639\u0631 \u0627\u0644\u0634\u0631\u0627\u0621 (\u0627\u0644\u062a\u0643\u0644\u0641\u0629)" in text:
    print("already applied")
    raise SystemExit(0)

p1 = Path("scripts/pageInventory_part1.b64").read_text(encoding="ascii").strip()
p2 = Path("scripts/pageInventory_part2.b64").read_text(encoding="ascii").strip()
NEW = base64.b64decode(p1 + p2).decode("utf-8")
if "function pageInventory" not in NEW or "sellPriceForm" not in NEW:
    raise SystemExit("invalid pageInventory payload")

start = text.index("function pageInventory() {")
end = text.index("function pageDashboard() {")
text = text[:start] + NEW + text[end:]

needle = "if (route === 'manage-bikes' && state.user) Promise.all([loadMotorcycles(),loadMotorcycleUnits()]).then(render);"
if "route === 'inventory' && state.user" not in text:
    if needle not in text:
        raise SystemExit("navigate needle missing")
    text = text.replace(
        needle,
        needle + "\n  if (route === 'inventory' && state.user) Promise.all([loadMotorcycles(),loadInventoryData()]).then(render);",
        1,
    )

old_cost = "  if (form.id === 'inventoryCostForm') {"
if "form.id === 'sellPriceForm'" not in text:
    if old_cost not in text:
        raise SystemExit("inventoryCostForm missing")
    sell = """  if (form.id === 'sellPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('\u0644\u064a\u0633 \u0644\u062f\u064a\u0643 \u0635\u0644\u0627\u062d\u064a\u0629 \u062a\u0639\u062f\u064a\u0644 \u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639','error'); return; }
    if (!supabase) { toast('\u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u063a\u064a\u0631 \u0645\u062a\u0627\u062d','error'); return; }
    const fd = new FormData(form);
    const bikeId = form.dataset.bikeId;
    const price = Number(fd.get('price'));
    if (!bikeId || !(price >= 0)) { toast('\u0623\u062f\u062e\u0644 \u0633\u0639\u0631\u0627\u064b \u0635\u062d\u064a\u062d\u0627\u064b','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    const { error } = await supabase.from('motorcycles').update({ price }).eq('id', bikeId);
    if (btn) btn.disabled = false;
    if (error) { toast(error.message || '\u062a\u0639\u0630\u0631 \u062d\u0641\u0638 \u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639','error'); return; }
    await Promise.all([loadMotorcycles(), loadInventoryData()]);
    render();
    toast('\u062a\u0645 \u062a\u062d\u062f\u064a\u062b \u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639','success');
    return;
  }
"""
    text = text.replace(old_cost, sell + old_cost, 1)

text = text.replace(
    '<p class="page-sub">\u0628\u064a\u0639 \u0645\u0628\u0627\u0634\u0631 \u0645\u0646 \u0627\u0644\u0645\u0639\u0631\u0636 \u2014 \u0644\u0627 \u064a\u062d\u062a\u0627\u062c \u0627\u0644\u0639\u0645\u064a\u0644 \u0625\u0644\u0649 \u062d\u0633\u0627\u0628 \u062f\u062e\u0648\u0644</p>',
    '<p class="page-sub">\u0646\u0638\u0627\u0645 \u0627\u0644\u0628\u064a\u0639 \u062f\u0627\u062e\u0644 \u0627\u0644\u0645\u0639\u0631\u0636 \u0645\u0639 \u062f\u0639\u0645 \u0627\u0644\u0645\u0627\u0633\u062d \u0627\u0644\u0636\u0648\u0626\u064a (\u0634\u0627\u0633\u064a\u0647/\u0628\u0627\u0631\u0643\u0648\u062f). \u0639\u0646\u062f \u0625\u062a\u0645\u0627\u0645 \u0627\u0644\u0628\u064a\u0639 \u062a\u064f\u0633\u062c\u0651\u064e\u0644 \u0627\u0644\u0641\u0627\u062a\u0648\u0631\u0629 \u0648\u062a\u064f\u062e\u0631\u062c \u0627\u0644\u0648\u062d\u062f\u0629 \u0645\u0646 \u0627\u0644\u0639\u0631\u0636 \u062a\u0644\u0642\u0627\u0626\u064a\u0627\u064b \u0645\u0639 \u0627\u0644\u0625\u0628\u0642\u0627\u0621 \u0639\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u0628\u064a\u0639.</p>',
    1,
)

APP.write_text(text, encoding="utf-8")
print("applied", APP.stat().st_size)
