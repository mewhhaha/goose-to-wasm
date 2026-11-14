#!/usr/bin/env python3
"""Check that the capability inventory covers the pinned frontend vocabulary.

This verifies inventory completeness and evidence paths, not semantic support.
Execution qualification remains the responsibility of the differential suites.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# The pinned frontend vocabulary, frozen from upstream's src/ast.h and
# src/builtins.h at the contract revision (--upstream re-derives it).
VOCABULARY = ROOT / "tests" / "conformance" / "upstream-vocabulary.json"
HEADERS = ("src/ast.h", "src/builtins.h")


def inventory_names(ast: str, builtins: str) -> dict[str, set[str]]:
    nodes = re.search(r"enum NodeKind[^\{]*\{(.*?)\};", ast, re.S)
    arrays = re.search(r"enum ArrayKind[^\{]*\{(.*?)\};", ast, re.S)
    if nodes is None or arrays is None:
        raise ValueError("cannot locate pinned frontend enums")
    return {
        "builtins": set(re.findall(r"^\s*F\((B_\w+),", builtins, re.M)),
        "nodes": set(re.findall(r"\bNK_\w+\b", nodes[1])),
        "arrays": set(re.findall(r"^\s*(A_\w+)\s*,", arrays[1], re.M)),
    }


def pinned_headers(upstream: Path, revision: str) -> dict[str, str]:
    """The vocabulary headers at the pin, read from an upstream git checkout."""
    return {path: subprocess.run(["git", "-C", str(upstream), "show", f"{revision}:{path}"], check=True,
                                 capture_output=True, text=True).stdout for path in HEADERS}


def frozen(revision: str, headers: dict[str, str]) -> dict:
    names = inventory_names(headers["src/ast.h"], headers["src/builtins.h"])
    return {"schema": "goose-upstream-vocabulary-v1", "upstream_revision": revision,
            "header_sha256": {path: hashlib.sha256(text.encode()).hexdigest() for path, text in headers.items()},
            **{group: sorted(values) for group, values in names.items()}}


def check(manifest: dict, vocabulary: dict) -> list[str]:
    errors = []
    pins = json.loads((ROOT / "toolchain.json").read_text())
    if manifest.get("upstream_revision") != pins["upstream_contract"]["revision"]:
        errors.append("capability inventory revision differs from toolchain pin")
    if vocabulary.get("upstream_revision") != pins["upstream_contract"]["revision"]:
        errors.append("frozen vocabulary revision differs from toolchain pin")
    for group in ("builtins", "nodes", "arrays"):
        expected = set(vocabulary.get(group, []))
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
    parser.add_argument("--manifest", type=Path, default=ROOT / "docs" / "capabilities.json")
    parser.add_argument("--vocabulary", type=Path, default=VOCABULARY)
    parser.add_argument("--upstream", type=Path,
                        help="upstream Goose git checkout: re-derive the vocabulary at the pin and require the frozen copy to match")
    parser.add_argument("--write", action="store_true", help="with --upstream, rewrite the frozen vocabulary")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    errors = []
    if args.upstream:
        revision = json.loads((ROOT / "toolchain.json").read_text())["upstream_contract"]["revision"]
        derived = frozen(revision, pinned_headers(args.upstream, revision))
        if args.write:
            args.vocabulary.write_text(json.dumps(derived, indent=2) + "\n")
        elif json.loads(args.vocabulary.read_text()) != derived:
            errors.append(f"{args.vocabulary.name} differs from upstream {revision}")
    errors += check(manifest, json.loads(args.vocabulary.read_text()))
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
