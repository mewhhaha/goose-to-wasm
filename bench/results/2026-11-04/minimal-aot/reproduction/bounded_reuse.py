#!/usr/bin/env python3
"""Project pinned members from the immutable leaf-and-loads archive set.

This helper intentionally returns archive/member identities only. It never
imports the prior alias or document namespace into a new publication.
"""
from pathlib import Path
import gzip
import hashlib
import json


PUBLICATION = Path("bench/results/2026-11-04/leaf-and-loads")
INDEX_SCHEMA = "goose-leaf-and-loads-objects-v1"


def read(path):
    return json.loads(path.read_text())


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bounded_archive_records(root):
    """Read archive records from the pinned prior index, never its aliases."""
    root = Path(root).resolve()
    publication = root / PUBLICATION
    manifest = read(publication / "SHA256.json")
    index_path = publication / "archives.json.gz"
    if sha256(index_path) != manifest["archives.json.gz"]:
        raise ValueError("prior archive index digest differs from its publication manifest")

    spec_path = publication / "reproduction" / "spec.json"
    if sha256(spec_path) != manifest["reproduction/spec.json"]:
        raise ValueError("prior bundle specification digest differs from its publication manifest")
    spec = read(spec_path)
    reused = spec["reuse"]["archives"]
    allowed = set(reused.values()) | {f"evidence-{number:03}.tar.gz" for number in range(3)}
    with gzip.open(index_path, "rt", encoding="utf-8") as stream:
        index = json.load(stream)
    if index.get("schema") != INDEX_SCHEMA:
        raise ValueError("prior archive index schema differs")
    if set(index["archives"]) != allowed:
        raise ValueError("prior physical archive inventory differs from its bounded specification")

    records = {}
    for name in sorted(allowed):
        record = index["archives"][name]
        records[name] = {
            "path": name,
            "sha256": record["sha256"],
            "bytes": record["bytes"],
            "members": record["members"],
        }
    return records


def select_members(records, wanted_sha256):
    """Return only requested SHA-to-archive/member pins; reject ambiguity."""
    wanted = set(wanted_sha256)
    selected = {}
    for archive, record in records.items():
        for member, identity in record["members"].items():
            value = identity["sha256"]
            if value not in wanted:
                continue
            location = {"archive": archive, "member": member, **identity}
            previous = selected.get(value)
            if previous is not None and previous != location:
                raise ValueError(f"ambiguous prior object identity: {value}")
            selected[value] = location
    missing = wanted - selected.keys()
    if missing:
        raise ValueError(f"prior object identities unavailable: {sorted(missing)}")
    return selected
