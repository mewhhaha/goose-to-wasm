#!/usr/bin/env python3
"""Check that the capability inventory covers the pinned frontend vocabulary.

This verifies inventory completeness and evidence paths, not semantic support.
Execution qualification remains the responsibility of the differential suites.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def inventory_names(source: Path) -> dict[str, set[str]]:
    ast = (source / "src" / "ast.h").read_text()
    builtins = (source / "src" / "builtins.h").read_text()
    nodes = re.search(r"enum NodeKind[^\{]*\{(.*?)\};", ast, re.S)
    arrays = re.search(r"enum ArrayKind[^\{]*\{(.*?)\};", ast, re.S)
    if nodes is None or arrays is None:
        raise ValueError("cannot locate pinned frontend enums")
    return {
        "builtins": set(re.findall(r"^\s*F\((B_\w+),", builtins, re.M)),
        "nodes": set(re.findall(r"\bNK_\w+\b", nodes[1])),
        "arrays": set(re.findall(r"^\s*(A_\w+)\s*,", arrays[1], re.M)),
    }


def check(manifest: dict, source: Path) -> list[str]:
    errors = []
    pins = json.loads((ROOT / "toolchain.json").read_text())
    if manifest.get("upstream_revision") != pins["revision"]:
        errors.append("capability inventory revision differs from toolchain pin")
    for group, expected in inventory_names(source).items():
        observed = set(manifest["capabilities"].get(group, {}))
        if expected != observed:
            errors.append(f"{group}: missing={sorted(expected-observed)}, extra={sorted(observed-expected)}")
    for group, entries in manifest["capabilities"].items():
        for name, entry in entries.items():
            label = f"{group}/{name}"
            if entry.get("status") not in {"qualified_subset", "frontend_only", "pending"}:
                errors.append(f"{label}: unknown status")
            if not entry.get("scope"):
                errors.append(f"{label}: missing scope")
            fixtures = entry.get("fixtures", [])
            if entry.get("status") == "qualified_subset" and not fixtures:
                errors.append(f"{label}: qualified subset has no fixture")
            for path in fixtures + entry.get("boundary_fixtures", []):
                if not (ROOT / path).is_file():
                    errors.append(f"{label}: missing evidence path {path}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "build" / "source")
    parser.add_argument("--manifest", type=Path, default=ROOT / "docs" / "capabilities.json")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    errors = check(manifest, args.source_dir)
    for error in errors:
        print(error)
    entries = [entry for group in manifest["capabilities"].values() for entry in group.values()]
    counts = {status: sum(entry["status"] == status for entry in entries)
              for status in ("qualified_subset", "frontend_only", "pending")}
    print(f"{len(entries)} inventoried capabilities: {counts}; {len(errors)} inventory errors")
    print("A qualified subset is not whole-capability parity; read each scope and run its qualification suite.")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
