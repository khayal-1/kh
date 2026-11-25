#!/usr/bin/env python3
from pathlib import Path
import base64
parts = [Path(f"scripts/apply_next_p{i}.b64").read_text(encoding="ascii").strip() for i in range(3)]
data = base64.b64decode("".join(parts))
Path("scripts/apply-prices-tools.py").write_bytes(data)
print("merged", len(data))
