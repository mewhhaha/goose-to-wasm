"""Read-only build inventory. Allocate each top-level directory to one group."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[5]
sizes = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    size, path = line.split("\t", 1)
    sizes[path] = int(size)
total = sizes.pop("build")
# Match literal replay paths in committed docs, scripts and benchmark receipts.
reference_commit = "054d463d1e91800f6909604e46f2bf08a12d457d"
references = subprocess.run(["git", "grep", "-I", "-h", "-o", "-E",
                             "build/[[:alnum:]_.-]+", reference_commit, "--", "bench", "tests", "scripts", "docs", "README.md"],
                            cwd=root, capture_output=True, check=True).stdout.decode().splitlines()
referenced = set(references)
cache = {"build/cache", "build/qualify-cache", "build/em-cache"}
tools = {"build/bin", "build/emsdk", "build/langbench-native", "build/langbench-goose-source", "build/wasmtime-host"}
groups = Counter()
rows = []
for path, size in sorted(sizes.items(), key=lambda p: -p[1]):
    if path in cache:
        kind = "rebuildable caches"
    elif path in tools:
        kind = "installed tools and inputs"
    elif path in referenced or path == "build/six-hills-1118":
        kind = "referenced or active run trees"
    else:
        kind = "unclassified; inspect before removal"
    groups[kind] += size
    rows.append({"path": path, "allocated_bytes": size, "group": kind})
remainder = total - sum(sizes.values())
groups["root files and directory metadata"] = remainder
if remainder < 0:
    raise ValueError("inconsistent disk inventory")
out = {"method": "du -B1 -d1 build; hard links counted once; live workspace snapshot",
       "reference_commit": reference_commit, "total_allocated_bytes": total, "groups_bytes": groups, "directories": rows}
# Bound duplicate scanning to a completed cold/warm qualification pair.
# Same inode means an existing hard link. Its second pathname uses no extra blocks.
cold = root / "build/qz/cold/conformance/artifacts"
warm = root / "build/qz/warm/conformance/artifacts"
def artifact_files(directory):
    for p in directory.glob("*/*"):
        if p.name in {"program", "program.wasm", "program.c"} and p.is_file():
            yield p

if cold.is_dir() and warm.is_dir():
    cold_digests = {}
    def file_hash(path):
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, "sha256").hexdigest()
    for path in artifact_files(cold):
        stat = path.stat()
        cold_digests.setdefault((stat.st_size, file_hash(path)), set()).add((stat.st_dev, stat.st_ino))
    matched = 0
    distinct = set()
    logical_bytes = 0
    for path in artifact_files(warm):
        stat = path.stat()
        inode = (stat.st_dev, stat.st_ino)
        original = cold_digests.get((stat.st_size, file_hash(path)))
        if original:
            matched += 1
            if inode not in original and inode not in distinct:
                distinct.add(inode)
                logical_bytes += stat.st_size
    out["generated_duplicates"] = {"first": str(cold.relative_to(root)), "second": str(warm.relative_to(root)),
                                   "matching_warm_paths": matched, "independent_warm_inodes": len(distinct),
                                   "duplicate_logical_bytes": logical_bytes}
Path(sys.argv[2]).write_text(json.dumps(out, indent=2) + "\n")
print({key: round(v / 2**30, 2) for key, v in groups.items()})
