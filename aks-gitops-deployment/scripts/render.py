#!/usr/bin/env python3
"""Render an environment exactly as Argo CD would, for validation in CI.

1. Renders argocd/applications (the root app-of-apps) and argocd/applicationsets.
2. For every generated Application, renders its Helm source with the same
   valueFiles resolution Argo CD uses (paths relative to the chart, $values ref).
   Remote charts (cert-manager, Airflow, Traefik, Argo CD) are rendered from a
   local chart cache directory: <cache>/<chart>-<version>/ (helm pull --untar).

Usage: render.py <env> --out DIR [--chart-cache DIR] [--kube-version 1.36.0] [--helm helm]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def helm_template(helm: str, release: str, chart: Path, namespace: str, value_files: list[Path], kube: str, values_obj: dict | None = None) -> str:
    cmd = [helm, "template", release, str(chart), "-n", namespace, "--kube-version", kube, "--include-crds"]
    for f in value_files:
        cmd += ["-f", str(f)]
    tmp = None
    if values_obj:
        tmp = ROOT / ".render-values.yaml"
        tmp.write_text(yaml.safe_dump(values_obj))
        cmd += ["-f", str(tmp)]
    try:
        out = subprocess.run(cmd, check=True, capture_output=True, text=True)  # noqa: S603 - fixed argv
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stderr)
        raise
    finally:
        if tmp:
            tmp.unlink(missing_ok=True)
    return out.stdout


def resolve(chart_dir: Path, files: list[str], ignore_missing: bool) -> list[Path]:
    out = []
    for f in files:
        p = (ROOT / f.removeprefix("$values/")) if f.startswith("$values/") else (chart_dir / f).resolve()
        if p.exists():
            out.append(p)
        elif not ignore_missing:
            raise FileNotFoundError(p)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("env")
    ap.add_argument("--out", required=True)
    ap.add_argument("--chart-cache")
    ap.add_argument("--kube-version", default="1.36.0")
    ap.add_argument("--helm", default="helm")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    env_file = ROOT / "environments" / a.env / "argocd.yaml"

    root = helm_template(a.helm, "root", ROOT / "argocd/applications", "argocd", [env_file], a.kube_version)
    appsets = helm_template(a.helm, "appsets", ROOT / "argocd/applicationsets", "argocd", [env_file], a.kube_version)
    (out / "00-root-applications.yaml").write_text(root + appsets)

    apps = [d for d in yaml.safe_load_all(root) if d and d.get("kind") == "Application"]
    # Expand the microservices ApplicationSet (list generator) into Applications.
    env_values = yaml.safe_load(env_file.read_text())
    for svc in env_values["services"]:
        apps.append({
            "metadata": {"name": svc},
            "spec": {"destination": {"namespace": "apps"}, "source": {"path": f"helm/{svc}", "helm": {"releaseName": svc, "valueFiles": [
                f"../../environments/{a.env}/infrastructure.yaml", f"../../environments/{a.env}/apps/{svc}.yaml"]}}},
        })

    rendered = 0
    for app in apps:
        name, spec = app["metadata"]["name"], app["spec"]
        ns = spec["destination"]["namespace"]
        sources = spec.get("sources") or [spec["source"]]
        chart_src = next(s for s in sources if "ref" not in s)
        helm = chart_src.get("helm", {})
        ignore = helm.get("ignoreMissingValueFiles", False)
        if "chart" in chart_src:
            if not a.chart_cache:
                print(f"skip {name}: remote chart {chart_src['chart']} (no --chart-cache)")
                continue
            chart_dir = Path(a.chart_cache) / f"{chart_src['chart']}-{chart_src['targetRevision']}"
            if not chart_dir.exists():
                print(f"skip {name}: {chart_dir} not in cache")
                continue
        else:
            chart_dir = ROOT / chart_src["path"]
        files = resolve(chart_dir, helm.get("valueFiles", []), ignore)
        manifest = helm_template(a.helm, helm.get("releaseName", name), chart_dir, ns, files, a.kube_version, helm.get("valuesObject"))
        (out / f"{name}.yaml").write_text(manifest)
        rendered += 1
        print(f"rendered {name} ({chart_dir.relative_to(ROOT) if ROOT in chart_dir.parents else chart_dir.name}) <- {[str(f.relative_to(ROOT)) if ROOT in f.parents else f.name for f in files]}")
    print(f"{rendered} applications rendered into {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
