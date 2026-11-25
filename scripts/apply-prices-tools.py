#!/usr/bin/env python3
from pathlib import Path
import base64
APP = Path("app.js")
text = APP.read_text(encoding="utf-8")
if "sellPriceForm" in text and "\u0633\u0639\u0631 \u0627\u0644\u0634\u0631\u0627\u0621 (\u0627\u0644\u062a\u0643\u0644\u0641\u0629)" in text:
    print("already applied")
    raise SystemExit(0)
print("placeholder - full script needed")
