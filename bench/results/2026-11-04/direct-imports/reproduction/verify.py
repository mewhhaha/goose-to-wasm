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
SCHEMA = "goose-direct-imports-objects-v1"
PRIOR_SCHEMA = "goose-minimal-aot-objects-v1"
PRIOR_MANIFEST_SHA256 = "c52b99e6d4faeec6db87b3f651ede829ed162f96adc9953d7aa3255db7c0bdb8"
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


def prior_allowlist(index):
    """An exact pinned index is the finite allowlist, never prior aliases."""
    archives = index["archives"]
    require(len(archives) == 30, "prior archive count differs from release pin")
    local = {name for name, record in archives.items() if not record["external"]}
    require(local == {f"evidence-{number:03}.tar.gz" for number in range(6)},
            "prior local archive inventory differs")
    require(all(name in local or name.startswith("../leaf-and-loads/") for name in archives),
            "prior physical archive namespace differs")
    return set(archives)


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
                 ("prepared_aot", "aot_sha256"),
                 ("precompiled", "precompiled_sha256"), ("library", "library_sha256"),
                 ("sdk_archive", "sdk_archive_sha256"), ("result", "result_sha256"),
                 ("log", "log_sha256"), ("report", "report_sha256"),
                 ("failed_checkpoint", "failed_checkpoint_sha256"), ("driver_log", "driver_log_sha256"),
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
        if "module_bytes" in value or value.get("backend") in ("native", "direct", "c-wasm"):
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


def command_logs(value):
    if isinstance(value, dict):
        if value.get("format") == "tar.gz" and Path(value.get("path", "")).name == "command-logs.tar.gz":
            yield value
        for child in value.values():
            yield from command_logs(child)
    elif isinstance(value, list):
        for child in value:
            yield from command_logs(child)


def logical_command_logs(data, metadata):
    groups = {}
    total = 0
    count = 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            path = safe(member.name)
            require(member.isfile() and path.name in {"command.json", "stdout", "stderr", "result.json"},
                    "unsafe streamed command-log member")
            group = groups.setdefault(str(path.parent), {})
            require(path.name not in group, "duplicate streamed command-log member")
            with archive.extractfile(member) as stream:
                group[path.name] = stream.read()
            require(len(group[path.name]) == member.size, "truncated streamed command log")
            total += member.size
            count += 1
    require(count == metadata["files"] and total == metadata["uncompressed_bytes"],
            "streamed command-log logical inventory differs")
    for group in groups.values():
        require(set(group) == {"command.json", "stdout", "stderr", "result.json"}, "incomplete command-log group")
        group["command"] = json.loads(group["command.json"])
        group["result"] = json.loads(group["result.json"])
        require(isinstance(group["command"], list) and all(isinstance(x, str) for x in group["command"]),
                "invalid retained command")
        result = group["result"]
        require(not result["error"] and result["stdout_sha256"] == hashlib.sha256(group["stdout"]).hexdigest() and
                result["stderr_sha256"] == hashlib.sha256(group["stderr"]).hexdigest(),
                "retained command result differs from logical byte streams")
    return groups


def bind_replay_logs(document, metadata, groups):
    root = PurePosixPath(metadata["path"]).parent
    required = {"version"}
    if "aot_host_build" in document:
        required.add("aot-version")
    preparations = {item["wasm_sha256"]: item for item in document["preparations"]}
    for row in document["preparations"] + document["results"]:
        directory = str(PurePosixPath(row["logs"]).relative_to(root))
        required.add(directory)
        require(directory in groups, "replay row logical logs absent")
        group = groups[directory]
        require(group["result"]["exit_code"] == row["exit_code"], "replay row/log exit differs")
        if "stdout_sha256" in row:
            require(group["result"]["stdout_sha256"] == row["stdout_sha256"] and
                    group["result"]["stderr_sha256"] == row["stderr_sha256"] and
                    group["stdout"].decode(errors="replace") == row["stdout"] and
                    group["stderr"].decode(errors="replace") == row["stderr"], "replay row/log output differs")
            mode = row["mode"]
            command = group["command"]
            expected_host = document["host_build"]["host_sha256"]
            if mode == "precompiled-minimal":
                expected_host = document["aot_host_build"]["host_sha256"]
            require(document["input_sha256"].get(command[0]) == expected_host, "replay log host identity differs")
            expected_tail = ["--no-cache", row["module"]]
            if mode == "wasm-no-parallel":
                expected_tail.append("--no-parallel-compilation")
            if mode in {"precompiled-no-parallel", "precompiled-minimal"}:
                prepared = preparations[row["wasm_sha256"]]
                expected_tail = ["--precompiled", prepared["artifact"]]
                if mode == "precompiled-no-parallel":
                    expected_tail.insert(0, "--no-parallel-compilation")
            require(command[1:] == expected_tail, "replay logical command differs")
        else:
            command = group["command"]
            expected_tail = ["--no-cache", "--no-parallel-compilation"]
            if "aot_host_build" in document:
                expected_tail += ["--aot-profile", "minimal"]
            expected_tail += ["--compile", row["module"], row["artifact"]]
            require(command == [document["configuration"]["host"], *expected_tail] and row["exit_code"] == 0,
                    "preparation logical command differs")
    require(set(groups) == required, "logical replay command inventory differs")
    for name in required & {"version", "aot-version"}:
        group = groups[name]
        require(group["command"][1:] == ["--version"] and group["result"]["exit_code"] == 0 and
                group["stdout"] == ("Wasmtime " + document["wasmtime"] + "\n").encode() and group["stderr"] == b"",
                "logical version probe differs")


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
    require(retention["schema"] == "goose-direct-imports-retention-v1", "retention schema differs")
    index = load(out / "archives.json.gz")
    require(index["schema"] == SCHEMA, "object index schema differs")
    require(set(index) == {"schema", "archives", "inputs", "documents", "reports", "public_bindings", "reuse", "identity_only"},
            "unexpected index namespace")
    binding = index["reuse"]
    require(binding["manifest_sha256"] == retention["specification"]["prior_manifest_sha256"] == PRIOR_MANIFEST_SHA256,
            "immediate predecessor release pin differs")
    prior = (out / "../minimal-aot").resolve()
    if prior_root is not None:
        prior = Path(prior_root).resolve()
    require(binding["publication"] == "../minimal-aot", "prior publication differs")
    require(digest(prior / "SHA256.json") == binding["manifest_sha256"], "prior manifest differs")
    prior_manifest = load(prior / "SHA256.json")
    require(prior_manifest["archives.json.gz"] == binding["index_sha256"] == digest(prior / "archives.json.gz"),
            "prior index differs from bound manifest")
    prior_index = load(prior / "archives.json.gz")
    require(prior_index["schema"] == PRIOR_SCHEMA and set(binding["archive_allowlist"]) == prior_allowlist(prior_index),
            "prior physical archive inventory differs")
    prior_archives = prior_index["archives"]
    del prior_index  # No historical aliases or documents enter the current index.
    wanted_payloads = {row["sha256"] for row in index["documents"].values()}
    compacted_names = {"raw-logs.tar.gz", "raw-logs-direct.tar.gz", "raw-log-inventory.json", "raw-log-inventory-direct.json", "command-logs.tar.gz", "command-log-inventory.json"}
    wanted_payloads.update(location["sha256"] for original, location in index["inputs"].items()
                           if Path(original.rpartition("@")[0]).name in compacted_names or
                           Path(original.rpartition("@")[0]).name.endswith(("raw-logs.tar.gz", ".inventory.json")))
    payloads = {}
    verified_objects = set()
    inventories = {}
    for name, record in index["archives"].items():
        external = record["external"]
        if external:
            prefix = "../minimal-aot/"
            require(name.startswith(prefix), f"invalid prior archive prefix: {name}")
            prior_name = name[len(prefix):]
            require(prior_name in set(binding["archive_allowlist"]), f"unbounded prior archive: {name}")
            old = prior_archives[prior_name]
            require(record["sha256"] == old["sha256"] and record["bytes"] == old["bytes"], "prior archive pin differs")
            require(all(member not in old["members"] or old["members"][member] == identity
                        for member, identity in record["members"].items()),
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
    streamed_log_members = 0
    checked_streams = {}
    for original, location in index["documents"].items():
        require(index["inputs"][original + "@" + location["sha256"]] == location, "document input edge absent")
        document = json.loads(payloads[location["sha256"]])
        if isinstance(document, dict) and document.get("status") == "verified-compacted":
            inventory = json.loads(payloads[document["inventory_sha256"]])
            if "entries" in inventory:
                entries = inventory["entries"]
                inventory = {row["path"]: {key: row[key] for key in ("sha256", "bytes")} for row in entries}
                require(len(inventory) == len(entries), "duplicate compacted raw-log inventory entry")
            found = {}
            with tarfile.open(fileobj=io.BytesIO(payloads[document["archive_sha256"]]), mode="r:gz") as archive:
                for member in archive:
                    safe(member.name)
                    require(member.isfile() and member.name not in found, "invalid compacted raw-log member")
                    with archive.extractfile(member) as stream:
                        identity = hashlib.file_digest(stream, "sha256").hexdigest()
                    found[member.name] = {"sha256": identity, "bytes": member.size}
            files = document.get("files", document.get("removed_files"))
            payload_bytes = document.get("payload_bytes", document.get("removed_payload_bytes"))
            require(found == inventory and len(found) == files and
                    sum(row["bytes"] for row in found.values()) == payload_bytes,
                    "compacted raw-log payload inventory differs")
            compacted_payloads += len(found)
        for metadata in command_logs(document):
            # Failed/incomplete experimental streams remain retained opaque bytes.
            if not isinstance(document, dict) or document.get("status") not in {"pass", "passed"}:
                continue
            require(metadata["closed"] and metadata["complete"] and not metadata["error"],
                    "incomplete streamed command logs")
            require(metadata["sha256"] in verified_objects, "streamed command-log bytes unavailable")
            identity = metadata["sha256"]
            if identity not in checked_streams:
                checked_streams[identity] = logical_command_logs(payloads[identity], metadata)
                streamed_log_members += metadata["files"]
            else:
                require(sum(len(group[name]) for group in checked_streams[identity].values()
                            for name in ("command.json", "stdout", "stderr", "result.json")) == metadata["uncompressed_bytes"] and
                        len(checked_streams[identity]) * 4 == metadata["files"], "inconsistent repeated stream metadata")
            if document.get("schema") == "goose-native-wasmtime-qualification-v1":
                bind_replay_logs(document, metadata, checked_streams[identity])
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
            "compacted_payloads": compacted_payloads, "streamed_log_members": streamed_log_members}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("publication", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.publication), indent=2, sort_keys=True))
