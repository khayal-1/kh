#!/usr/bin/env python3
from pathlib import Path
import base64

APP = Path("app.js")
text = APP.read_text(encoding="utf-8")
if "sellPriceForm" in text and "\u0633\u0639\u0631 \u0627\u0644\u0634\u0631\u0627\u0621" in text:
    print("already applied")
    raise SystemExit(0)

NEW = base64.b64decode(
    "ZnVuY3Rpb24gcGFnZUludmVudG9yeSgpIHsKICBjb25zdCB1ID0gY3VycmVudFVzZXIoKTsKICBpZiAo"
    "IXUgfHwgIVsnc3RhZmYnLCAnYWRtaW4nLCAnbWFuYWdlcicsICdvd25lciddLmluY2x1ZGVzKHUu"
    "cm9sZSkpIHJldHVybiBwYWdlTG9naW4oKTsKICBpZiAodS5yb2xlID09PSAnc3RhZmYnICYmICFo"
    "YXNBbnlQZXJtaXNzaW9uKCdjYXRhbG9nX3ZpZXcnLCAnY2F0YWxvZ19tYW5hZ2UnKSkgcmV0dXJu"
    "IHBhZ2VOb1Blcm1pc3Npb24oKTsKICBjb25zdCBiaWtlcyA9IChnZXQoREIuQklLRVMpIHx8IFtd"
    "KS5maWx0ZXIoKGIpID0+ICFiLmlzX2RlbW8pOwogIGNvbnN0IGNvc3RNYXAgPSBuZXcgTWFwKChz"
    "dGF0ZS5pbnZlbnRvcnlDb3N0cyB8fCBbXSkubWFwKCh4KSA9PiBbeC5tb3RvcmN5Y2xlX2lkLCB4"
    "XSkpOwogIGNvbnN0IGNhbkVkaXRQcmljZSA9IGhhc1JvbGUoJ2FkbWluJywgJ21hbmFnZXInLCAn"
    "b3duZXInKSB8fCBoYXNQZXJtaXNzaW9uKCdjYXRhbG9nX21hbmFnZScpOwogIGNvbnN0IGNhblNh"
    "bGVzID0gaGFzUm9sZSgnYWRtaW4nLCAnbWFuYWdlcicsICdvd25lcicpIHx8IGhhc1Blcm1pc3Np"
    "b24oJ3NhbGVzX21hbmFnZScpOwogIGNvbnN0IHJvd3MgPSBiaWtlcy5tYXAoKGIpID0+IHsKICAg"
    "IGNvbnN0IGNvc3QgPSBjb3N0TWFwLmdldChiLmlkKSB8fCB7fTsKICAgIGNvbnN0IHVuaXRDb3N0"
    "ID0gTnVtYmVyKGNvc3QudW5pdF9jb3N0IHx8IDApOwogICAgY29uc3Qgc2VsbCA9IE51bWJlcihi"
    "LnByaWNlIHx8IDApOwogICAgY29uc3QgbWFyZ2luID0gc2VsbCAtIHVuaXRDb3N0OwogICAgY29u"
    "c3QgbWFyZ2luUGN0ID0gc2VsbCA+IDAgPyAoKG1hcmdpbiAvIHNlbGwpICogMTAwKSA6IDA7CiAg"
    "ICBjb25zdCBzYyA9IGIuc3RvY2sgPD0gMCA/ICdvdXQnIDogYi5zdG9jayA8PSAyID8gJ2xvdycg"
    "OiAnYXZhaWxhYmxlJzsKICAgIGNvbnN0IHN0ID0gYi5zdG9jayA8PSAwID8gJ9mG2YHYsCcgOiBi"
    "LnN0b2NrIDw9IDIgPyAn2YXZhtiu2YHYticgOiAn2YXYqtmI2YHYsSc7CiAgICBjb25zdCBpbWcg"
    "PSAoYi5pbWFnZXMgJiYgYi5pbWFnZXNbMF0pIHx8ICcnOwogICAgY29uc3QgcHJpY2VDZWxsID0g"
    "Y2FuRWRpdFByaWNlCiAgICAgID8gYDxmb3JtIGlkPSJzZWxsUHJpY2VGb3JtIiBjbGFzcz0iaW5s"
    "aW5lLWZvcm0iIGRhdGEtYmlrZS1pZD0iJHtlc2MoYi5pZCl9Ij4KICAgICAgICAgICA8aW5wdXQg"
    "dHlwZT0ibnVtYmVyIiBuYW1lPSJwcmljZSIgbWluPSIwIiBzdGVwPSIwLjAxIiB2YWx1ZT0iJHtz"
    "ZWxsfSIgcmVxdWlyZWQgc3R5bGU9Im1heC13aWR0aDoxMjBweCI+CiAgICAgICAgICAgPGJ1dHRv"
    "biBjbGFzcz0iYnRuIGJ0bi1vdXRsaW5lIGJ0bi1zbSIgdHlwZT0ic3VibWl0Ij7YrdmB2Lg8L2J1"
    "dHRvbj4KICAgICAgICAgPC9mb3JtPmAKICAgICAgOiBgPHNwYW4gY2xhc3M9InRleHQtcmVkIiBz"
    "dHlsZT0iZm9udC13ZWlnaHQ6OTAwIj4ke21vbmV5KHNlbGwpfTwvc3Bhbj5gOwogICAgcmV0dXJu"
    "IGA8dHI+CiAgICAgIDx0ZD48aW1nIGNsYXNzPSJtaW5pLWltZyIgc3JjPSIke2VzYyhzYWZlSW1h"
    "Z2VVcmwoaW1nKSl9IiBhbHQ9IiIgbG9hZGluZz0ibGF6eSI+PC90ZD4KICAgICAgPHRkPjxiPiR7"
    "ZXNjKGIubmFtZSl9PC9iPjxicj48c21hbGw+JHtlc2MoYi5tb2RlbCB8fCAnJyl9IMK3ICR7ZXNj"
    "KGIuY2F0ZWdvcnkgfHwgJycpfTwvc21hbGw+PC90ZD4KICAgICAgPHRkPiR7dW5pdENvc3QgPyBt"
    "b25leSh1bml0Q29zdCkgOiAnPHNwYW4gY2xhc3M9ImhpbnQiPti62YrYsSDZhdiz2KzZkdmEPC9z"
    "cGFuPid9PC90ZD4KICAgICAgPHRkPiR7cHJpY2VDZWxsfTwvdGQ+CiAgICAgIDx0ZD4ke3VuaXRD"
    "b3N0ID8gbW9uZXkobWFyZ2luKSArICc8YnI+PHNtYWxsPicgKyBtYXJnaW5QY3QudG9GaXhlZCgx"
    "KSArICclPC9zbWFsbD4nIDogJ+KAlCd9PC90ZD4KICAgICAgPHRkPiR7Yi5zdG9ja308L3RkPgog"
    "ICAgICA8dGQ+PHNwYW4gY2xhc3M9InN0YXR1cy1waWxsICR7c2N9Ij4ke3N0fTwvc3Bhbj48L3Rk"
    "PgogICAgICA8dGQ+PHNwYW4gY2xhc3M9InN0YXR1cy1waWxsIj4ke2VzYyhiLnN0YXR1cyB8fCAn"
    "4oCUJyl9PC9zcGFuPjwvdGQ+CiAgICA8L3RyPmA7CiAgfSkuam9pbignJyk7CgogIHJldHVybiBg"
    "CiAgICA8aDIgY2xhc3M9InBhZ2UtdGl0bGUiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS10YWdzIj48"
    "L2k+INin2YTYo9iz2LnYp9ixPC9oMj4KICAgIDxwIGNsYXNzPSJwYWdlLXN1YiI+2KfZhNiq2K3Z"
    "g9mFINin2YTZg9in2YXZhCDYqNin2YTYo9iz2LnYp9ixOiDYudix2LYg2LPYudixINin2YTYtNix"
    "2KfYoSAo2KfZhNiq2YPZhNmB2KkpINmI2LPYudixINin2YTYqNmK2Lkg2YXYuSDYpdmF2YPYp9mG"
    "2YrYqSDYqti52K/ZitmE2YfYjCDZiNix2KjYtyDYudix2YjYtiDYp9mE2KrZgtiz2YrYtyDZiNin"
    "2YTZg9iq2KfZhNmI2KwuPC9wPgoKICAgIDxkaXYgY2xhc3M9InN0YXRzLWdyaWQiPgogICAgICA8"
    "ZGl2IGNsYXNzPSJzdGF0LWNhcmQiPjxkaXYgY2xhc3M9InN0YXQtaWNvbiI+PGkgY2xhc3M9ImZh"
    "LXNvbGlkIGZhLW1vdG9yY3ljbGUiPjwvaT48L2Rpdj48ZGl2IGNsYXNzPSJzdGF0LWxhYmVsIj7Y"
    "t9ix2KfYstin2Kog2YXYs9mR2YQqPC9kaXY+PGRpdiBjbGFzcz0ic3RhdC12YWx1ZSI+JHtiaWtl"
    "cy5sZW5ndGh9PC9kaXY+PC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9InN0YXQtY2FyZCI+PGRpdiBj"
    "bGFzcz0ic3RhdC1pY29uIj48aSBjbGFzcz0iZmEtc29saWQgZmEtYm94ZXMtc3RhY2tlZCI+PC9p"
    "PjwvZGl2PjxkaXYgY2xhc3M9InN0YXQtbGFiZWwiPtil2KzZhdin2YTZiiDYp9mE2YXYrtiy2YjZ"
    "hjwvZGl2PjxkaXYgY2xhc3M9InN0YXQtdmFsdWUiPiR7YmlrZXMucmVkdWNlKChzLGIpPT5zK051"
    "bWJlcihiLnN0b2NrfHwwKSwwKX08L2Rpdj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ic3RhdC1j"
    "YXJkIj48ZGl2IGNsYXNzPSJzdGF0LWljb24iPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jb2lucyI+"
    "PC9pPjwvZGl2PjxkaXYgY2xhc3M9InN0YXQtbGFiZWwiPtmC2YrZhdipINin2YTYqNmK2Lkg2KfZ"
    "hNmF2KrZiNmC2LnYqTwvZGl2PjxkaXYgY2xhc3M9InN0YXQtdmFsdWUiIHN0eWxlPSJmb250LXNp"
    "emU6MS4wNXJlbSI+JHttb25leShiaWtlcy5yZWR1Y2UoKHMsYik9PnMrTnVtYmVyKGIucHJpY2V8"
    "fDApKk51bWJlcihiLnN0b2NrfHwwKSwwKSl9PC9kaXY+PC9kaXY+CiAgICA8L2Rpdj4KCiAgICA8"
    "ZGl2IGNsYXNzPSJwYW5lbCI+CiAgICAgIDxkaXYgY2xhc3M9InBhbmVsLXRpdGxlIj48aSBjbGFz"
    "cz0iZmEtc29saWQgZmEtc2NyZXdkcml2ZXItd3JlbmNoIj48L2k+INij2K/ZiNin2Kog2KfZhNij"
    "2LPYudin2LEg2YjYp9mE2YPYqtin2YTZiNisPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9Imludm9p"
    "Y2UtYWN0aW9ucyI+CiAgICAgICAgJHtjYW5FZGl0UHJpY2UgPyAnPGJ1dHRvbiBjbGFzcz0iYnRu"
    "IGJ0bi1wcmltYXJ5IGJ0bi1zbSIgZGF0YS1uYXY9Im1hbmFnZS1iaWtlcyI+PGkgY2xhc3M9ImZh"
    "LXNvbGlkIGZhLW1vdG9yY3ljbGUiPjwvaT4g2KfZhNmF2LnYsdi2IC8g2KfZhNmD2KrYp9mE2YjY"
    "rCAo2KXYttin2YHYqSDZiNiq2LnYr9mK2YQpPC9idXR0b24+JyA6ICcnfQogICAgICAgICR7Y2Fu"
    "U2FsZXMgPyAnPGJ1dHRvbiBjbGFzcz0iYnRuIGJ0bi1vdXRsaW5lIGJ0bi1zbSIgZGF0YS1uYXY9"
    "InNhbGVzLXRvb2xzIj48aSBjbGFzcz0iZmEtc29saWQgZmEtZmlsZS1pbnZvaWNlLWRvbGxhciI+"
    "PC9pPiDYudix2YjYtiDYp9mE2KrZgtiz2YrYtyDZiNiq2LnYr9mK2YTZh9inPC9idXR0b24+JyA6"
    "ICcnfQogICAgICAgICR7KGhhc1JvbGUoJ2FkbWluJywnbWFuYWdlcicsJ293bmVyJyl8fGhhc1Bl"
    "cm1pc3Npb24oJ2NhdGFsb2dfbWFuYWdlJyl8fGhhc1Blcm1pc3Npb24oJ2ZpbmFuY2VfbWFuYWdl"
    "JykpID8gJzxidXR0b24gY2xhc3M9ImJ0biBidG4tb3V0bGluZSBidG4tc20iIGRhdGEtbmF2PSJp"
    "bnZlbnRvcnktdG9vbHMiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS13YXJlaG91c2UiPjwvaT4g2KrZ"
    "g9mE2YHYqSDYp9mE2YjYrdiv2Kkg2YjYp9mE2KzYsdivPC9idXR0b24+JyA6ICcnfQogICAgICAg"
    "IDxidXR0b24gY2xhc3M9ImJ0biBidG4tb3V0bGluZSBidG4tc20iIGRhdGEtbmF2PSJwb3MiPjxp"
    "IGNsYXNzPSJmYS1zb2xpZCBmYS1jYXNoLXJlZ2lzdGVyIj48L2k+INin2YTYqNmK2Lkg2YXZhiDY"
    "p9mE2YXYudix2LY8L2J1dHRvbj4KICAgICAgPC9kaXY+CiAgICAgIDxwIGNsYXNzPSJoaW50IG10"
    "LTIiPtiz2LnYsSDYp9mE2LTYsdin2KEgPSDYqtmD2YTZgdipINin2YTZiNit2K/YqSDZhdmGINin"
    "2YTZhdmI2LHYry/Yp9mE2KzYsdivLiDYs9i52LEg2KfZhNio2YrYuSDZgtin2KjZhCDZhNmE2KrY"
    "udiv2YrZhCDZhdio2KfYtNix2Kkg2YXZhiDYp9mE2KzYr9mI2YQg2KXZhiDZg9in2YbYqiDZhNiv"
    "2YrZgyDYtdmE2KfYrdmK2Kkg2KfZhNmD2KrYp9mE2YjYrC4g2LnYsdmI2LYg2KfZhNiq2YLYs9mK"
    "2Lcg2KrZj9iv2KfYsSDZhdmGINij2K/Yp9ipINi52LHZiNi2INin2YTYqtmC2LPZiti3LjwvcD4K"
    "ICAgIDwvZGl2PgoKICAgIDxkaXYgY2xhc3M9InBhbmVsIHByaW50YWJsZS1wYW5lbCI+CiAgICAg"
    "IDxkaXYgY2xhc3M9InBhbmVsLXRpdGxlIj48aSBjbGFzcz0iZmEtc29saWQgZmEtbGlzdCI+PC9p"
    "PiDYrNiv2YjZhCDYp9mE2KPYs9i52KfYsSAoJHtiaWtlcy5sZW5ndGh9KTwvZGl2PgogICAgICA8"
    "ZGl2IGNsYXNzPSJ0YWJsZS13cmFwIj48dGFibGU+CiAgICAgICAgPHRoZWFkPjx0cj4KICAgICAg"
    "ICAgIDx0aD7Yp9mE2LXZiNix2Kk8L3RoPjx0aD7Yp9mE2LXZhtmBIC8g2KfZhNmF2YjYr9mK2YQ8"
    "L3RoPgogICAgICAgICAgPHRoPtiz2LnYsSDYp9mE2LTYsdin2KE8L3RoPjx0aD7Ys9i52LEg2KfZ"
    "hNio2YrYuTwvdGg+PHRoPtmH2KfZhdi0INin2YTYsdio2K08L3RoPgogICAgICAgICAgPHRoPtin"
    "2YTZhdiu2LLZiNmGPC90aD48dGg+2KfZhNiq2YjZgdixPC90aD48dGg+2K3Yp9mE2Kkg2KfZhNi5"
    "2LHYtjwvdGg+CiAgICAgICAgPC90cj48L3RoZWFkPgogICAgICAgIDx0Ym9keT4KICAgICAgICAg"
    "ICR7cm93cyB8fCAnPHRyPjx0ZCBjb2xzcGFuPSI4Ij7ZhNinINiq2YjYrNivINij2LXZhtin2YEg"
    "2YHZiiDYp9mE2YPYqtin2YTZiNisPC90ZD48L3RyPid9CiAgICAgICAgPC90Ym9keT4KICAgICAg"
    "PC90YWJsZT48L2Rpdj4KICAgIDwvZGl2PmA7Cn0KCg=="
).decode("utf-8")

if "function pageInventory" not in NEW or "sellPriceForm" not in NEW:
    raise SystemExit("invalid NEW payload")

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

APP.write_text(text, encoding="utf-8")
print("applied", APP.stat().st_size)
