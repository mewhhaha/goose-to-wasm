#!/usr/bin/env python3
"""Read the one pinned immediate predecessor's physical object index only."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import gzip
import hashlib
import json
import re
import tarfile

PUBLICATION = Path('bench/results/2026-11-04/minimal-aot')
MANIFEST_SHA256 = 'c52b99e6d4faeec6db87b3f651ede829ed162f96adc9953d7aa3255db7c0bdb8'


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def bounded_archive_records(root):
    from verify import prior_allowlist, require
    publication = Path(root).resolve() / PUBLICATION
    require(sha256(publication / 'SHA256.json') == MANIFEST_SHA256,
            'prior manifest differs from explicit immediate-predecessor pin')
    manifest = json.loads((publication / 'SHA256.json').read_text())
    index_path = publication / 'archives.json.gz'
    require(sha256(index_path) == manifest['archives.json.gz'], 'prior physical index digest differs')
    with gzip.open(index_path, 'rt', encoding='utf-8') as stream:
        index = json.load(stream)
    require(index['schema'] == 'goose-minimal-aot-objects-v1', 'prior physical index schema differs')
    allowed = prior_allowlist(index)
    return {name: {key: index['archives'][name][key] for key in ('sha256', 'bytes', 'members')}
            for name in sorted(allowed)}


def discover_required_members(root, records, required):
    """Recover explicit guest bytes hidden by old projections, without old indexes.

    The pinned compressed archive digest remains the authority. The independent
    verifier checks each selected actual member, including these extra projections.
    """
    from verify import require, safe
    known = {row['sha256'] for record in records.values() for row in record['members'].values()}
    missing = set(required) - known
    discovered = 0
    for name, record in sorted(records.items()):
        if not missing:
            break
        with tarfile.open(Path(root) / PUBLICATION / name, 'r:gz') as archive:
            seen = set()
            for member in archive:
                safe(member.name)
                require(member.isfile() and member.name not in seen, 'unsafe prior physical member')
                seen.add(member.name)
                embedded = {part for part in Path(member.name).parts if re.fullmatch('[0-9a-f]{64}', part)}
                if embedded and not (embedded & missing):
                    continue
                with archive.extractfile(member) as stream:
                    identity = hashlib.file_digest(stream, 'sha256').hexdigest()
                if identity in missing:
                    record['members'][member.name] = {'sha256': identity, 'bytes': member.size}
                    missing.remove(identity)
                    discovered += 1
    require(not missing, 'explicit compiler-reference guest bytes unavailable: ' + str(sorted(missing)))
    return discovered
