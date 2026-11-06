#!/usr/bin/env python3
"""Emit the build matrix for images whose sources changed between two commits.
Usage: changed-images.py <before-sha> <after-sha> [all|name,name]"""

import json
import re
import subprocess
import sys
from pathlib import Path

catalog = json.loads((Path(__file__).resolve().parents[1] / "images.json").read_text())
before, after = sys.argv[1], sys.argv[2]
REF = re.compile(r"^([0-9a-f]{7,40}|HEAD(~[0-9]+)?)$")
if not (REF.match(before) and REF.match(after)):
    sys.exit("refs must be commit SHAs or HEAD~n")
selection = sys.argv[3] if len(sys.argv) > 3 else ""

if selection == "all":
    names = list(catalog)
elif selection:
    names = [n.strip() for n in selection.split(",") if n.strip() in catalog]
else:
    zero = before.strip("0") == ""
    cmd = ["git", "diff", "--name-only", f"{before}..{after}"] if not zero else ["git", "ls-files"]
    # Arguments are validated commit refs above; no shell is involved.
    changed = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.splitlines()  # noqa: S603
    names = [n for n, spec in catalog.items() if any(f.startswith(p) for f in changed for p in spec["paths"])]

matrix = {"include": [{"name": n, "dockerfile": catalog[n]["dockerfile"]} for n in names]}
print(f"matrix={json.dumps(matrix)}")
print(f"any={'true' if names else 'false'}")
