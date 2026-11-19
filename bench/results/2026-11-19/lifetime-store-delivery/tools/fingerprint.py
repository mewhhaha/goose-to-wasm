"""Instrument an unpacked compiler source copy for lifetime state comparisons."""

import argparse
from pathlib import Path


def insert_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"Expected exactly one occurrence of {old!r}")
    return source.replace(old, new)


def instrument(path, limit):
    source = path.read_text()
    helper = Path(__file__).with_name("fingerprint.inc").read_text()
    for old, new in [
        ("import model;", "import model;\nimport os;"),
        ("fn check_lifetimes(", helper + "\nfn check_lifetimes("),
        ("        l.pass += 1;\n", '        l.pass += 1; dbg_fingerprint(p,l,"begin");\n'),
        (
            "for failure in l.failures { life_error(p, l, failure.node, failure.message); }",
            'for failure in l.failures { life_error(p, l, failure.node, failure.message); } dbg_fingerprint(p,l,"failed");',
        ),
        (
            "l.discovery = false;\n    for root",
            'dbg_fingerprint(p,l,"discovered"); l.discovery = false;\n    for root',
        ),
        (
            "if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }",
            'dbg_fingerprint(p,l,"validated"); if p.diagnostics.len == 0 { '
            "life_export_provenance(p, l); life_refresh_named_results(p); dbg_proofs(p); }",
        ),
        ("LIFE_CONCRETE_FRAMES: i64 = 4096", f"LIFE_CONCRETE_FRAMES: i64 = {limit}"),
    ]:
        source = insert_once(source, old, new)
    if limit < 4096 and "l.items.len <= 65536" in source:
        source = insert_once(source, "l.items.len <= 65536", "l.items.len <= 0")
    path.write_text(source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_copy", type=Path, help="unpacked source tree to instrument")
    parser.add_argument("--class-limit", type=int, default=4096)
    args = parser.parse_args()
    instrument(args.source_copy / "selfhost/checker_lifetimes.goose", args.class_limit)
