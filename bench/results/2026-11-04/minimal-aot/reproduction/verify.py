#!/usr/bin/env python3
"""Read-only offline byte/inventory verification. No build, guest or engine execution."""
import sys
sys.dont_write_bytecode = True

from pathlib import Path, PurePosixPath
import argparse
import gzip
import hashlib
import io
import json
import re
import tarfile

SHA = re.compile(r"[0-9a-f]{64}\Z")
SCHEMA = "goose-minimal-aot-objects-v1"
PRIOR_SCHEMA = "goose-leaf-and-loads-objects-v1"
EXAMPLES = {"squares", "tour", "functions", "errors", "sieve", "sorting", "sudoku", "maze", "vm", "life"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    if str(path).endswith(".gz"):
        with gzip.open(path, "rt", encoding="utf-8") as stream:
            return json.load(stream)
    return json.loads(Path(path).read_text())


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe(name):
    path = PurePosixPath(name)
    require(name and not path.is_absolute() and ".." not in path.parts and "\\" not in name,
            f"unsafe relative name: {name}")
    return path


def prior_allowlist():
    counts = {"fresh-construction": 2, "functions-calls": 4, "functions-forwarding": 8,
              "merge-bounds": 2, "runtime-stencil": 2, "strided-stores": 2}
    names = {f"../../2026-11-03/{name}/evidence-{number:03}.tar.gz"
             for name, count in counts.items() for number in range(count)}
    names.update(f"../byte-scans/evidence-{number:03}.tar.gz" for number in range(2))
    names.update(f"evidence-{number:03}.tar.gz" for number in range(3))
    return names


def fingerprints(value):
    """Only explicit path/SHA pairs in declared current documents; never follow JSON."""
    if isinstance(value, dict):
        for path, identity in value.items():
            if isinstance(identity, str) and SHA.fullmatch(identity) and ("/" in path or Path(path).suffix):
                yield path, identity
            if isinstance(identity, dict) and SHA.fullmatch(str(identity.get("sha256", ""))) and "/" in path:
                yield path, identity["sha256"]
        pairs = [("path", "sha256"), ("artifact", "artifact_sha256"), ("artifact", "sha256"),
                 ("source", "source_sha256"), ("source", "sha256"), ("compiler", "compiler_sha256"),
                 ("host", "host_sha256"), ("native_host", "host_sha256"),
                 ("module", "wasm_sha256"), ("wasm", "wasm_sha256"), ("wasm", "sha256"),
                 ("output", "module_sha256"), ("baseline_artifact", "baseline_sha256"),
                 ("candidate_artifact", "candidate_sha256"), ("aot", "aot_sha256"), ("aot_path", "aot_sha256"),
                 ("precompiled", "precompiled_sha256"), ("library", "library_sha256"),
                 ("sdk_archive", "sdk_archive_sha256"), ("result", "result_sha256"),
                 ("log", "log_sha256"), ("report", "report_sha256"),
                 ("archive", "archive_sha256"), ("inventory", "inventory_sha256"),
                 ("original_report", "original_report_sha256"), ("full_report", "full_report_sha256"),
                 ("frozen_canonical", "canonical_sha256"),
                 ("disassembly", "disassembly_sha256"), ("stats_path", "stats_sha256"),
                 ("cache_config", "cache_config_sha256"),
                 ("host_build_metadata_path", "host_build_metadata_sha256")]
        for path_key, sha_key in pairs:
            path, identity = value.get(path_key), value.get(sha_key)
            if isinstance(path, str) and isinstance(identity, str) and SHA.fullmatch(identity):
                if "/" in path or Path(path).suffix:
                    yield path, identity
        for child in value.values():
            yield from fingerprints(child)
    elif isinstance(value, list):
        for child in value:
            yield from fingerprints(child)


def guest_sha256(value):
    if isinstance(value, dict):
        fields = {"artifact_sha256", "module_sha256", "wasm_sha256", "aot_sha256", "precompiled_sha256"}
        if "module_bytes" in value:
            fields.add("sha256")
        for field in fields:
            identity = value.get(field)
            if isinstance(identity, str) and SHA.fullmatch(identity):
                yield identity
        for child in value.values():
            yield from guest_sha256(child)
    elif isinstance(value, list):
        for child in value:
            yield from guest_sha256(child)


def validate_reports(reports, compiler):
    for name, report in reports.items():
        require(report.get("status") in {"pass", "passed"}, f"incomplete report: {name}")
    for name in ("examples.json", "host.json", "lifecycle.json"):
        report = reports[name]
        require({row["name"] for row in report["examples"]} == EXAMPLES, f"ten-example coverage: {name}")
        environment = report["environment"]
        identity = environment.get("compiler_sha256")
        if identity is None:
            identity = environment.get("compiler_source_identity", {}).get("compiler_sha256")
        if identity is None:
            identity = environment.get("compiler", {}).get("sha256")
        require(identity == compiler, f"compiler differs: {name}")
        require(not report.get("failures"), f"failed observations: {name}")
    for key in ("source_hashes_still_match", "input_paths_still_match", "compiler_hash_still_matches",
                "artifact_hashes_still_match"):
        require(reports["examples.json"].get(key) is True, f"example identity check failed: {key}")


def verify(out, require_seal=True, prior_root=None):
    out = Path(out).resolve()
    if require_seal:
        manifest = load(out / "SHA256.json")
        actual = {str(path.relative_to(out)) for path in out.rglob("*") if path.is_file()}
        require(actual == set(manifest) | {"SHA256.json"}, "public manifest inventory differs")
        for name, expected in manifest.items():
            safe(name)
            require(digest(out / name) == expected, f"public digest differs: {name}")
    require(not any(out.rglob("__pycache__")), "verification must not create bytecode caches")
    retention = load(out / "retention.json")
    require(retention["schema"] == "goose-minimal-aot-retention-v1", "retention schema differs")
    index = load(out / "archives.json.gz")
    require(index["schema"] == SCHEMA, "object index schema differs")
    require(set(index) == {"schema", "archives", "inputs", "documents", "reports", "public_bindings", "reuse", "identity_only"},
            "unexpected index namespace")
    binding = index["reuse"]
    prior = (out / "../leaf-and-loads").resolve()
    if prior_root is not None:
        prior = Path(prior_root).resolve()
    require(binding["publication"] == "../leaf-and-loads", "prior publication differs")
    require(set(binding["archive_allowlist"]) == prior_allowlist(), "25-archive allowlist differs")
    require(digest(prior / "SHA256.json") == binding["manifest_sha256"], "prior manifest differs")
    prior_manifest = load(prior / "SHA256.json")
    require(prior_manifest["archives.json.gz"] == binding["index_sha256"] == digest(prior / "archives.json.gz"),
            "prior index differs from bound manifest")
    prior_index = load(prior / "archives.json.gz")
    require(prior_index["schema"] == PRIOR_SCHEMA and set(prior_index["archives"]) == prior_allowlist(),
            "prior physical archive inventory differs")
    prior_archives = prior_index["archives"]
    del prior_index  # No historical aliases or documents enter the current index.
    wanted_payloads = {row["sha256"] for row in index["documents"].values()}
    compacted_names = {"raw-logs.tar.gz", "raw-logs-direct.tar.gz", "raw-log-inventory.json", "raw-log-inventory-direct.json"}
    wanted_payloads.update(location["sha256"] for original, location in index["inputs"].items()
                           if Path(original.rpartition("@")[0]).name in compacted_names)
    payloads = {}
    verified_objects = set()
    inventories = {}
    for name, record in index["archives"].items():
        external = record["external"]
        if external:
            prefix = "../leaf-and-loads/"
            require(name.startswith(prefix), f"invalid prior archive prefix: {name}")
            prior_name = name[len(prefix):]
            require(prior_name in prior_allowlist(), f"unbounded prior archive: {name}")
            old = prior_archives[prior_name]
            require(record["sha256"] == old["sha256"] and record["bytes"] == old["bytes"], "prior archive pin differs")
            require(all(old["members"].get(member) == identity for member, identity in record["members"].items()),
                    "prior member projection differs")
            path = prior / prior_name
        else:
            require(safe(name).parent == PurePosixPath("."), "new archive must be local")
            path = out / name
        require(path.stat().st_size == record["bytes"] and digest(path) == record["sha256"], f"archive digest differs: {name}")
        seen = set()
        found = {}
        raw_bytes = 10240
        with tarfile.open(path, "r:gz") as archive:
            for member in archive:
                safe(member.name)
                require(member.isfile() and member.name not in seen, "unsafe or duplicate archive member")
                seen.add(member.name)
                raw_bytes += 512 + ((member.size + 511) // 512) * 512
                if member.name not in record["members"]:
                    require(external, "unindexed new archive member")
                    continue
                expected = record["members"][member.name]["sha256"]
                with archive.extractfile(member) as stream:
                    if expected in wanted_payloads:
                        data = stream.read()
                        identity = hashlib.sha256(data).hexdigest()
                        payloads[identity] = data
                    else:
                        identity = hashlib.file_digest(stream, "sha256").hexdigest()
                actual = {"sha256": identity, "bytes": member.size}
                require(actual == record["members"][member.name], f"member identity differs: {member.name}")
                found[member.name] = actual
                verified_objects.add(actual["sha256"])
        require(found == record["members"], f"archive member inventory differs: {name}")
        if not external:
            require(raw_bytes <= retention["specification"]["max_raw_archive_bytes"], "new archive exceeds size bound")
        inventories[name] = len(found)
    for original, location in index["inputs"].items():
        path, separator, expected = original.rpartition("@")
        require(separator and expected == location["sha256"], "input edge identity differs")
        record = index["archives"][location["archive"]]["members"][location["member"]]
        require(record == {key: location[key] for key in ("sha256", "bytes")}, "input edge location differs")
        require(expected in verified_objects, f"missing retained bytes: {path}")
    for original, reason in index["identity_only"].items():
        require(reason and original not in index["inputs"], "invalid identity-only exception")
        path = original.rpartition("@")[0]
        require(Path(path).suffix not in {".wasm", ".cwasm", ".bin", ".goose", ".h", ".cpp"}, "required artifact omitted")
        require(not Path(path).name.startswith("goose"), "measured compiler or host omitted")
    compacted_payloads = 0
    for original, location in index["documents"].items():
        require(index["inputs"][original + "@" + location["sha256"]] == location, "document input edge absent")
        document = json.loads(payloads[location["sha256"]])
        if document.get("status") == "verified-compacted":
            inventory = json.loads(payloads[document["inventory_sha256"]])
            found = {}
            with tarfile.open(fileobj=io.BytesIO(payloads[document["archive_sha256"]]), mode="r:gz") as archive:
                for member in archive:
                    safe(member.name)
                    require(member.isfile() and member.name not in found, "invalid compacted raw-log member")
                    with archive.extractfile(member) as stream:
                        identity = hashlib.file_digest(stream, "sha256").hexdigest()
                    found[member.name] = {"sha256": identity, "bytes": member.size}
            require(found == inventory and len(found) == document["files"] and
                    sum(row["bytes"] for row in found.values()) == document["payload_bytes"],
                    "compacted raw-log payload inventory differs")
            compacted_payloads += len(found)
        require(set(guest_sha256(document)) <= verified_objects, f"required guest payload missing: {original}")
        for path, expected in fingerprints(document):
            key = path + "@" + expected
            require(key in index["inputs"] or key in index["identity_only"], f"document input edge absent: {path}")
    reports = {name: json.loads(payloads[location["sha256"]]) for name, location in index["reports"].items()}
    validate_reports(reports, retention["compiler_sha256"])
    for name, location in index["reports"].items():
        require(digest(out / name) == location["sha256"], f"public report differs: {name}")
    for name, location in index["public_bindings"].items():
        require(location["sha256"] in verified_objects, f"public binding bytes missing: {name}")
    if require_seal:
        readme = {location["sha256"] for original, location in index["inputs"].items()
                  if original.rpartition("@")[0].endswith("/copy/public-README.md")}
        require(len(readme) == 1 and digest(out / "README.md") in readme,
                "dated public README differs from retained reviewed copy")
    for row in binding["documents"]:
        require(row["relation"] in {"unchanged-compiler-qualification", "separately-collected-reference", "prior-host-only"},
                "ambiguous reused evidence role")
        safe(row["path"])
        require(prior_manifest[row["path"]] == row["sha256"], "reused document not bound by prior public manifest")
        require(row["sha256"] in verified_objects, "reused document bytes missing")
        location = row["location"]
        require(location["sha256"] == row["sha256"] and
                index["archives"][location["archive"]]["members"][location["member"]] ==
                {key: location[key] for key in ("sha256", "bytes")}, "reused document location differs")
        for path, expected in row["inputs"].items():
            require(path + "@" + expected in index["inputs"], f"qualified-reuse input absent: {path}")
    require(retention["counts"] == {"archives": len(index["archives"]), "inputs": len(index["inputs"]),
            "documents": len(index["documents"]), "identity_only": len(index["identity_only"])}, "retention counts differ")
    return {"status": "passed", "sealed": require_seal, "archives": inventories,
            "retained_inputs": len(index["inputs"]), "identity_only": len(index["identity_only"]),
            "compacted_payloads": compacted_payloads}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("publication", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.publication), indent=2, sort_keys=True))
