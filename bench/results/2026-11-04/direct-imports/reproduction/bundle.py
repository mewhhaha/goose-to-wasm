#!/usr/bin/env python3
"""Produce the bounded direct-imports publication after final measurement release."""
import sys
sys.dont_write_bytecode = True

from pathlib import Path
import argparse
import gzip
import json
import os
import shutil
import tarfile

from bounded_reuse import PUBLICATION, bounded_archive_records, discover_required_members
from verify import (SCHEMA, digest, fingerprints, guest_sha256, load, require, safe,
                    validate_reports, verify)

HERE = Path(__file__).resolve().parent


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_compressed(path, value):
    with path.open("wb") as raw:
        with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as stream:
            stream.write(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


class Bundle:
    def __init__(self, root, spec, preflight=False):
        self.root = root.resolve()
        self.spec = spec
        self.external_roots = []
        for declared in spec.get("external_roots", []):
            path = Path(declared)
            require(path.is_absolute() and str(path) == "/dev/shm/goose-remaining-hills-20261104",
                    "unexpected external evidence root")
            self.external_roots.append(path.resolve())
        self.out = self.root / spec["output"]
        require(spec["schema"] == "goose-direct-imports-bundle-spec-v1" and (spec["ready"] or preflight),
                "specification has not been released")
        self.preflight = preflight
        self.unresolved = []
        require(not self.out.exists(), "publication already exists; refusing to change sealed evidence")
        self.reports = {name: load(self.root / path) for name, path in spec["reports"].items()}
        validate_reports(self.reports, spec["compiler_sha256"])
        prior = self.root / PUBLICATION
        require(digest(prior / "SHA256.json") == spec["prior_manifest_sha256"], "prior manifest differs from explicit release pin")
        self.prior = bounded_archive_records(self.root)
        require(len(self.prior) == spec["prior_archive_count"], "prior archive count differs")
        reference = load(self.root / spec["semantic"]["baseline_report"])
        required_guests = set(guest_sha256(reference))
        original_guests = {row["sha256"] for record in self.prior.values() for row in record["members"].values()}
        cache_name = spec.get("prior_projection_cache")
        if cache_name:
            cache = Path(cache_name)
            require(any(cache.is_relative_to(root) for root in self.external_roots), "projection cache outside declared scratch")
            if cache.is_file():
                cached = load(cache)
                require(set(cached) == set(self.prior), "projection cache archive inventory differs")
                for name, record in self.prior.items():
                    saved = cached[name]
                    require(saved["sha256"] == record["sha256"] and saved["bytes"] == record["bytes"] and
                            all(saved["members"].get(member) == identity for member, identity in record["members"].items()),
                            "projection cache contradicts immutable prior metadata")
                    record["members"] = saved["members"]
        discover_required_members(self.root, self.prior, required_guests)
        discovered = len(required_guests - original_guests)
        self.by_sha = {}
        for name, record in sorted(self.prior.items()):
            for member, identity in sorted(record["members"].items()):
                safe(member)
                self.by_sha.setdefault(identity["sha256"], {"archive": name, "member": member, **identity})
        self.objects = {}
        self.cached = {}
        self.index = {"schema": SCHEMA, "archives": {}, "inputs": {}, "documents": {},
                      "reports": {}, "public_bindings": {}, "identity_only": {},
                      "reuse": {"publication": "../minimal-aot",
                          "manifest_sha256": spec["prior_manifest_sha256"],
                          "index_sha256": digest(prior / "archives.json.gz"),
                          "archive_allowlist": sorted(self.prior), "documents": [],
                          "discovered_reference_guest_members": discovered,
                          "policy": "Only physical archive/member projections; zero prior aliases imported. Missing explicit compiler-reference guests are discovered from the exact pinned physical archives and independently byte-verified."}}

    def absolute(self, path):
        path = Path(path)
        if path.is_absolute():
            return path
        return self.root / path

    def evidence_target(self, path):
        return path.is_relative_to(self.root) or any(path.is_relative_to(root) for root in self.external_roots)

    def location(self, identity):
        if identity in self.by_sha:
            location = self.by_sha[identity]
            prior_name = location["archive"]
            name = "../minimal-aot/" + prior_name
            prior = self.prior[prior_name]
            record = self.index["archives"].setdefault(name,
                {"external": True, "sha256": prior["sha256"], "bytes": prior["bytes"], "members": {}})
            record["members"][location["member"]] = {key: location[key] for key in ("sha256", "bytes")}
            return {**location, "archive": name}
        return {key: self.objects[identity][key] for key in ("sha256", "bytes", "member", "archive")}

    def add(self, path, expected=None, original=None):
        path = self.absolute(path)
        if original is None:
            original = str(path)
        if path.is_symlink():
            target = path.resolve(strict=True)
            require(self.evidence_target(target) and target.is_file(),
                    f"input alias target must be regular bytes in the repository or declared scratch root: {path}")
            path = target
        require(path.is_file(), f"required regular input is missing: {path}")
        if str(path) not in self.cached:
            self.cached[str(path)] = digest(path)
        identity = self.cached[str(path)]
        require(expected is None or expected == identity, f"input digest differs: {path}")
        if identity not in self.by_sha and identity not in self.objects:
            self.objects[identity] = {"path": path, "sha256": identity, "bytes": path.stat().st_size,
                                      "member": "objects/" + identity + "/" + path.name, "archive": None}
        location = self.location(identity)
        self.index["inputs"][str(original) + "@" + identity] = location
        return location

    def resolve(self, original, expected):
        key = original + "@" + expected
        if key in self.index["inputs"] or key in self.index["identity_only"]:
            return
        # Use prior immutable bytes or explicitly curated frozen snapshots before
        # consulting paths that may now contain the final product source.
        if expected in self.by_sha or expected in self.objects:
            self.index["inputs"][key] = self.location(expected)
            return
        reason = self.spec["identity_only"].get(key)
        if reason:
            require(Path(original).suffix not in {".wasm", ".cwasm", ".bin", ".goose", ".h", ".cpp"},
                    f"required artifact cannot be identity-only: {original}")
            require(not Path(original).name.startswith("goose"), "actual compiler and hosts must be retained")
            self.index["identity_only"][key] = reason
            return
        try:
            self.add(original, expected, original)
        except ValueError as error:
            if not self.preflight:
                raise
            self.unresolved.append({"path": original, "sha256": expected, "error": str(error)})

    def document(self, path, resolve_inputs=True):
        source = self.absolute(path)
        location = self.add(source)
        self.index["documents"][str(source)] = location
        if resolve_inputs:
            document = load(source)
            for original, expected in fingerprints(document):
                self.resolve(original, expected)
            for expected in guest_sha256(document):
                if self.preflight and expected not in self.by_sha and expected not in self.objects:
                    self.unresolved.append({"document": str(source), "sha256": expected, "error": "required measured guest bytes unavailable"})
                    continue
                require(expected in self.by_sha or expected in self.objects, f"required measured guest bytes unavailable: {expected}")
                self.index["inputs"]["sha256:" + expected + "@" + expected] = self.location(expected)
        return location

    def scan(self, folder):
        folder = self.absolute(folder)
        require(folder.is_dir() and not folder.is_symlink(), f"bounded input tree unavailable: {folder}")
        require(self.evidence_target(folder.resolve()), f"undeclared evidence tree root: {folder}")
        for directory, children, files in os.walk(folder):
            # The declared tree is already curated. Preserve all regular bytes,
            # including extensionless executables and engine cache payloads.
            children[:] = sorted(name for name in children if name not in {"__pycache__", ".git"})
            for name in children:
                require(not (Path(directory) / name).is_symlink(),
                        f"directory alias in bounded evidence tree: {Path(directory) / name}")
            for name in sorted(files):
                self.add(Path(directory) / name)

    def collect(self):
        experiment = load(self.root / self.spec["experiment_index"])
        for path in dict.fromkeys(self.spec["trees"] + experiment.get("trees", [])):
            self.scan(path)
        for item in self.spec["files"] + experiment.get("files", []):
            if self.preflight and isinstance(item, str) and item.endswith("/copy/public-README.md"):
                continue
            if isinstance(item, str):
                self.add(item)
            else:
                self.add(item["path"], item.get("sha256"))
        experiment_reports = [path for row in experiment.get("experiments", []) for path in row.get("reports", [])]
        documents = list(self.spec["reports"].values()) + self.spec["documents"] + experiment.get("documents", []) + experiment_reports
        for path in dict.fromkeys(documents):
            self.document(path)
        for name, path in self.spec["reports"].items():
            self.index["reports"][name] = self.index["documents"][str(self.absolute(path))]
        if not self.preflight:
            for path in self.spec["public_bindings"]:
                self.index["public_bindings"][path] = self.add(path)
        for original, identity in self.spec.get("retained_inputs", {}).items():
            self.resolve(original, identity)
        for item in self.spec["reused_documents"]:
            path = self.root / PUBLICATION / item["path"]
            expected = item["sha256"]
            location = self.add(path, expected)
            row = {"path": item["path"], "sha256": expected, "relation": item["relation"],
                   "description": item["description"], "location": location, "inputs": item.get("inputs", {})}
            self.index["reuse"]["documents"].append(row)
            # Selected qualified-reuse inputs are explicit, never recovered from
            # an old alias map or recursively traversed document graph.
            for original, identity in item.get("inputs", {}).items():
                self.resolve(original, identity)

    def archives(self, staging):
        maximum = self.spec["max_raw_archive_bytes"]
        groups = []
        group = []
        raw = 10240
        for item in sorted(self.objects.values(), key=lambda row: row["sha256"]):
            size = 512 + ((item["bytes"] + 511) // 512) * 512
            require(size + 10240 <= maximum, f"new object exceeds archive size bound: {item['path']}")
            if group and raw + size > maximum:
                groups.append(group)
                group = []
                raw = 10240
            group.append(item)
            raw += size
        if group:
            groups.append(group)
        for number, group in enumerate(groups):
            name = f"evidence-{number:03}.tar.gz"
            path = staging / name
            members = {}
            with path.open("wb") as raw_stream:
                with gzip.GzipFile(filename="", fileobj=raw_stream, mode="wb", mtime=0, compresslevel=6) as compressed:
                    with tarfile.open(fileobj=compressed, mode="w|") as archive:
                        for item in group:
                            require(digest(item["path"]) == item["sha256"], f"input changed during packaging: {item['path']}")
                            info = tarfile.TarInfo(item["member"])
                            info.size = item["bytes"]
                            info.mode = 0o644
                            with item["path"].open("rb") as stream:
                                archive.addfile(info, stream)
                            item["archive"] = name
                            members[item["member"]] = {key: item[key] for key in ("sha256", "bytes")}
            self.index["archives"][name] = {"external": False, "sha256": digest(path),
                                                   "bytes": path.stat().st_size, "members": members}
        # Locations were collected before local archive assignment.
        for section in ("inputs", "documents", "reports", "public_bindings"):
            for location in self.index[section].values():
                if location["archive"] is None:
                    location["archive"] = self.objects[location["sha256"]]["archive"]
        for row in self.index["reuse"]["documents"]:
            location = row["location"]
            if location["archive"] is None:
                location["archive"] = self.objects[location["sha256"]]["archive"]

    def publish(self):
        require(not self.preflight, "preflight cannot publish")
        self.collect()
        self.add("build/next-runtime-hills/final/bin/goose", self.spec["compiler_sha256"])
        staging = self.out.with_name(self.out.name + ".staging")
        require(not staging.exists(), "staging directory already exists")
        staging.mkdir(parents=True)
        # Staging is private until collection and every archive is complete.
        self.archives(staging)
        for name, path in self.spec["reports"].items():
            safe(name)
            shutil.copyfile(self.root / path, staging / name)
            require(digest(staging / name) == self.index["reports"][name]["sha256"], f"report changed: {name}")
        reproduction = staging / "reproduction"
        reproduction.mkdir()
        for name in ("bundle.py", "verify.py", "bounded_reuse.py", "audit_results.py"):
            shutil.copyfile(HERE / name, reproduction / name)
        write_json(reproduction / "spec.json", self.spec)
        write_compressed(staging / "archives.json.gz", self.index)
        write_json(staging / "retention.json", {"schema": "goose-direct-imports-retention-v1",
            "compiler_sha256": self.spec["compiler_sha256"], "policy": self.spec["policy"],
            "counts": {"archives": len(self.index["archives"]), "inputs": len(self.index["inputs"]),
                "documents": len(self.index["documents"]), "identity_only": len(self.index["identity_only"])},
            "specification": self.spec, "seal": "SHA256.json is written last by the independent final audit."})
        readme = self.root / self.spec["public_readme"]
        shutil.copyfile(readme, staging / "README.md")
        require(digest(staging / "README.md") == self.cached[str(readme)], "reviewed public README changed during publication")
        # The same offline path validates staging without requiring its future
        # independent seal; it never writes a manifest or mutates input evidence.
        result = verify(staging, require_seal=False)
        write_json(staging / "verification.json", result)
        staging.rename(self.out)
        return {"publication": str(self.out), **result}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--spec", type=Path, default=HERE / "spec.json")
    parser.add_argument("--release", action="store_true", help="explicitly confirms final benchmark CPU release")
    args = parser.parse_args()
    require(args.release, "production is disabled until the root agent grants final CPU release")
    print(json.dumps(Bundle(args.root, load(args.spec)).publish(), indent=2, sort_keys=True))
