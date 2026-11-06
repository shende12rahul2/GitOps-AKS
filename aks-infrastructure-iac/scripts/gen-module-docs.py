#!/usr/bin/env python3
"""Regenerate modules/*/README.md: hand-written header + generated inputs/outputs.

Usage: pip install python-hcl2 && python3 scripts/gen-module-docs.py
The header for each module lives in docs/module-headers/<module>.md.
"""
import json
import pathlib
import re

import hcl2

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = "<!-- BEGIN GENERATED -->"


def unquote(v):
    """python-hcl2 >= 7 keeps HCL quoting; normalise to plain values."""
    if isinstance(v, str):
        v = re.sub(r"^\$\{(.*)\}$", r"\1", v.strip(), flags=re.S)
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        return v
    if isinstance(v, dict):
        return {unquote(k): unquote(x) for k, x in v.items()}
    if isinstance(v, list):
        return [unquote(x) for x in v]
    return v


def clean(v):
    v = unquote(v)
    if not isinstance(v, str):
        v = json.dumps(v)
    return v.replace("\n", " ").replace("|", "\\|")


def table_inputs(path):
    if not path.exists():
        return "_None._"
    data = hcl2.load(path.open())
    rows = ["| Name | Description | Type | Default | Required |", "|---|---|---|---|:---:|"]
    for block in data.get("variable", []):
        for name, body in block.items():
            name = unquote(name)
            desc = clean(body.get("description", "")).strip()
            typ = clean(body.get("type", "any"))
            if len(typ) > 60:
                typ = typ[:57] + "..."
            has_default = "default" in body
            default = "" if not has_default else f"`{clean(body['default'])}`"
            rows.append(f"| `{name}` | {desc} | `{typ}` | {default} | {'no' if has_default else 'yes'} |")
    return "\n".join(rows)


def table_outputs(path):
    if not path.exists():
        return "_None._"
    data = hcl2.load(path.open())
    rows = ["| Name | Description |", "|---|---|"]
    for block in data.get("output", []):
        for name, body in block.items():
            rows.append(f"| `{unquote(name)}` | {clean(body.get('description', ''))} |")
    return "\n".join(rows)


def main():
    for mod in sorted((ROOT / "modules").iterdir()):
        if not mod.is_dir():
            continue
        header_file = ROOT / "docs" / "module-headers" / f"{mod.name}.md"
        header = header_file.read_text().rstrip() if header_file.exists() else f"# {mod.name}\n"
        body = (
            f"{header}\n\n{MARK}\n\n## Requirements\n\n| Name | Version |\n|---|---|\n"
            "| terraform | >= 1.11.0 |\n| azurerm | >= 5.0.0, < 6.0.0 |\n\n"
            f"## Inputs\n\n{table_inputs(mod / 'variables.tf')}\n\n"
            f"## Outputs\n\n{table_outputs(mod / 'outputs.tf')}\n"
        )
        (mod / "README.md").write_text(body)
        print(f"wrote {mod.name}/README.md")


if __name__ == "__main__":
    main()
