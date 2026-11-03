#!/usr/bin/env python3
"""Build, screen and independently confirm empirical kernel runtime references.

Custom --cases files use schema goose-runtime-reference-cases-v1 and a cases
list. Each case has name, source, test:{stdin,checksum}, run:{stdin,checksum};
source and optional source_files paths are relative to that JSON file. Extra
case metadata is retained. These adapters use the unchanged two-line port
protocol, not original full-program launch timing.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import shutil
import sys

import langarena as arena

ROOT = Path(__file__).resolve().parents[1]
ANCHOR = "native-gcc-O2-generic"
STAGES = ("build", "qualify", "pilot", "confirm")
COMMON = ["-fno-strict-aliasing", "-ffp-contract=off", "-fno-fast-math", "-fno-lto"]


def load_workloads(args):
    workloads = []
    if not args.no_langarena:
        for case in arena.load_manifest()["cases"]:
            if case["port"] is None:
                continue
            workloads.append({"name": case["name"], "source": str(arena.DATA / case["port"]["file"]),
                "test": {"stdin": arena.port_stdin(case, "test"), "checksum": case["test"]["checksum"]},
                "run": {"stdin": arena.port_stdin(case, "run"), "checksum": case["run"]["checksum"]},
                "metadata": {"track": "LangArena adapted", "catalog": case}, "source_files": []})
    for path in args.cases:
        document = json.loads(path.read_text())
        if document.get("schema") != "goose-runtime-reference-cases-v1":
            raise ValueError(f"unknown cases schema: {path}")
        for case in document["cases"]:
            row = {key: case[key] for key in ("name", "test", "run")}
            row["source"] = str((path.parent / case["source"]).resolve())
            row["source_files"] = [str(path.resolve())]
            row["source_files"] += [str((path.parent / name).resolve()) for name in case.get("source_files", [])]
            row["metadata"] = {key: value for key, value in case.items()
                               if key not in ("name", "source", "test", "run", "source_files")}
            workloads.append(row)
    selected = []
    names = set(); identifiers = set()
    for case in workloads:
        if args.filter and not any(text.lower() in case["name"].lower() for text in args.filter):
            continue
        case["id"] = re.sub(r"[^a-z0-9]+", "_", case["name"].lower()).strip("_")
        if not case["id"] or case["name"] in names or case["id"] in identifiers:
            raise ValueError(f"duplicate or empty workload identity: {case['name']}")
        names.add(case["name"]); identifiers.add(case["id"])
        if not Path(case["source"]).is_file():
            raise ValueError(f"missing source: {case['source']}")
        for profile in ("test", "run"):
            config = case[profile]
            if not isinstance(config["stdin"], str) or type(config["checksum"]) is not int or config["checksum"] < 0:
                raise ValueError(f"invalid {profile} protocol: {case['name']}")
        selected.append(case)
    if not selected:
        raise ValueError("no workloads selected")
    return selected


def variants(args):
    rows = [{"id": "direct-O2", "family": "direct", "optimization": 2}]
    native = {(compiler, level, march) for compiler in args.native_compilers
              for level in args.native_levels for march in args.march}
    native.add(("gcc", 2, "generic"))
    for compiler, level, march in sorted(native):
        rows.append({"id": f"native-{compiler}-O{level}-{march}", "family": "native",
                     "compiler": compiler, "optimization": level, "march": march})
    for level in args.c_wasm_levels:
        for simd in args.simd:
            rows.append({"id": f"c-wasm-O{level}-{simd}", "family": "c-wasm",
                         "optimization": level, "simd": simd})
    if args.wasm_opt:
        rows.append({"id": "direct-wasm-opt-O3", "family": "wasm-opt", "optimization": 3})
    return rows


def wasm_memories(path):
    data = path.read_bytes()
    if data[:8] != b"\0asm\x01\0\0\0":
        raise ValueError(f"not a WebAssembly module: {path}")
    def number(offset):
        value = 0
        for shift in range(0, 70, 7):
            if offset >= len(data):
                raise ValueError("truncated Wasm LEB")
            byte = data[offset]; offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value, offset
        raise ValueError("oversized Wasm LEB")
    offset = 8
    while offset < len(data):
        section = data[offset]; size, start = number(offset + 1)
        offset = start + size
        if offset > len(data):
            raise ValueError("truncated Wasm section")
        if section != 5:
            continue
        count, start = number(start); memories = []
        for _ in range(count):
            flags, start = number(start); _, start = number(start)
            if flags & 1:
                _, start = number(start)
            memories.append(32)
            if flags & 4:
                memories[-1] = 64
        return memories
    return []


def pick_reference(rows, candidates, samples):
    """Pilot-only selection: require every round, minimize median plus MAD."""
    scores = []
    for variant in candidates:
        values = [row["timed_region_seconds"] for row in rows
                  if row["variant"] == variant and row["status"] == "passed"]
        if len(values) != samples:
            continue
        summary = arena.summarize(values)
        scores.append((summary["median"] + summary["mad"], variant, summary))
    if not scores:
        return None
    score, variant, summary = min(scores)
    return {"variant": variant, "pilot_score_median_plus_mad_seconds": score,
            "pilot_timed_region_seconds": summary}


def derive_summaries(report):
    report["runtime_summary"] = []
    for phase in ("pilot", "confirm"):
        cells = sorted({(row["task"], row["variant"], row["engine"]) for row in report["observations"]
                        if row["phase"] == phase})
        for task, variant, engine in cells:
            rows = [row for row in report["observations"] if row["phase"] == phase and
                    (row["task"], row["variant"], row["engine"]) == (task, variant, engine) and row["status"] == "passed"]
            report["runtime_summary"].append({"phase": phase, "task": task, "variant": variant, "engine": engine,
                "timed_region_seconds": arena.summarize([row["timed_region_seconds"] for row in rows]),
                "process_wall_seconds": arena.summarize([row["wall_seconds"] for row in rows])})
    observations = {(row["task"], row["round"], row["variant"], row["engine"]): row["timed_region_seconds"]
                    for row in report["observations"] if row["phase"] == "confirm" and row["status"] == "passed"}
    paired = []; geometric = []
    for engine in report["configuration"]["engines"]:
        for comparison in ("gcc_O2_generic", "selected_native", "selected_wasm"):
            per_task = {}
            for case in report["workloads"]:
                task = case["name"]; selection = report["selection"].get(task, {})
                reference = ANCHOR; reference_engine = "native"
                if comparison == "selected_native":
                    reference = (selection.get("native") or {}).get("variant")
                if comparison == "selected_wasm":
                    reference = (selection.get("wasm", {}).get(engine) or {}).get("variant")
                    reference_engine = engine
                values = []
                for round_ in range(report["configuration"]["samples"]):
                    direct = observations.get((task, round_, "direct-O2", engine))
                    target = observations.get((task, round_, reference, reference_engine))
                    if direct is not None and target is not None:
                        values.append({"round": round_, "direct_over_reference": direct / target})
                per_task[task] = {row["round"]: row["direct_over_reference"] for row in values}
                paired.append({"task": task, "engine": engine, "comparison": comparison,
                               "reference": reference, "per_round": values,
                               "ratio": arena.summarize([row["direct_over_reference"] for row in values])})
            values = []
            for round_ in range(report["configuration"]["samples"]):
                missing = [task for task, rows in per_task.items() if round_ not in rows]
                value = None
                if not missing:
                    value = math.exp(sum(math.log(rows[round_]) for rows in per_task.values()) / len(per_task))
                values.append({"round": round_, "geometric_direct_over_reference": value, "missing_tasks": missing})
            geometric.append({"engine": engine, "comparison": comparison, "per_round": values,
                              "ratio": arena.summarize([row["geometric_direct_over_reference"] for row in values
                                                        if row["geometric_direct_over_reference"] is not None])})
    report["paired_ratios"] = paired; report["geometric_ratios"] = geometric


class Harness:
    def __init__(self, args):
        self.args = args; self.output = args.output_dir.resolve()
        self.workloads = load_workloads(args); self.variants = variants(args)
        self.tools = {"goose": self.locate(args.goose), "gcc": self.locate(args.cc),
                      "clang": self.locate(args.clang), "emcc": self.locate(args.emcc),
                      "node": self.locate(args.node), "host": self.locate(args.host)}
        if args.wasm_opt:
            self.tools["wasm_opt"] = self.locate(args.wasm_opt)
        llvm = Path(self.tools["emcc"]).parent.parent/"bin/clang"
        if llvm.is_file():
            self.tools["emscripten_clang"] = str(llvm.resolve())
        if args.cpu is not None:
            if not hasattr(os, "sched_getaffinity") or args.cpu not in os.sched_getaffinity(0):
                raise ValueError("selected runtime CPU is outside the allowed affinity")
            self.tools["taskset"] = self.locate("taskset")
        configuration = {key: value for key, value in vars(args).items() if key not in ("stages", "plan", "output_dir")}
        configuration = json.loads(json.dumps(configuration, default=str))
        self.output.mkdir(parents=True, exist_ok=True)
        path = self.output / "report.json"
        if path.is_file():
            self.report = json.loads(path.read_text())
            if (self.report["configuration"] != configuration or self.report["workloads"] != self.workloads or
                self.report["tools"] != self.tools):
                raise ValueError("resume configuration/workloads changed; choose a new output directory")
            self.verify()
        else:
            self.report = {"schema": "goose-runtime-reference-v1", "status": "running", "started_utc": arena.utc_now(),
                "configuration": configuration, "workloads": self.workloads, "variants": self.variants, "tools": self.tools,
                "inputs": {}, "artifacts": {}, "commands": [], "observations": [], "selection": {}, "failures": [], "phases": {},
                "runtime_phase_affinity": {}, "phase_metadata": {},
                "method": "Unchanged two-line kernel protocol and profile inputs. This task's builds/AOT preparation/tests finish before timings; "
                "unrelated shared-host activity is not stopped or assumed idle. Aggregate phase load averages are retained. "
                "Internal warmed bench_clock intervals are authoritative; process wall/preparation remain separate. "
                "Pilot-only references minimize median+MAD among native and direct/C-Wasm/optional wasm-opt candidates; fresh confirmation never reselects them. "
                "GCC-O2-generic remains an anchor. "
                "Ratios above one mean direct is slower. These are empirical references for this source/workload/toolchain/machine, "
                "not ceilings or confidence bounds. Close or noisy differences remain uncertain."}
            self.pin_inputs(); self.metadata(); self.save()

    @staticmethod
    def locate(value):
        found = shutil.which(str(value))
        if found:
            return str(Path(found).resolve())
        return str(Path(value).expanduser().resolve())

    def save(self):
        derive_summaries(self.report)
        temporary = self.output / "report.json.tmp"
        temporary.write_text(json.dumps(self.report, indent=2) + "\n")
        temporary.replace(self.output / "report.json")

    def pin(self, path):
        path = Path(path).resolve(); key = str(path); digest = arena.sha256(path)
        previous = self.report["inputs"].get(key)
        if previous is not None and previous != digest:
            raise ValueError(f"input changed: {path}")
        self.report["inputs"][key] = digest
        if path.suffix in (".goose", ".py", ".json", ".c", ".h", ".patch"):
            destination = self.output / "inputs" / digest / path.name
            if not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(path, destination)

    def pin_inputs(self):
        paths = [Path(__file__), ROOT/"bench/langarena.py", ROOT/"bench/langarena/manifest.json",
                 ROOT/"bench/langarena/test.json", ROOT/"bench/langarena/run.json", ROOT/"bench/host_input.c",
                 ROOT/"oracle/goose_wasm.py", ROOT/"scripts/run_wasm.mjs", ROOT/"toolchain.json"]
        paths += [Path(value) for value in self.tools.values() if Path(value).is_file()]
        compiler = Path(self.tools["goose"])
        paths += list((compiler.parent/"stdlib").rglob("*.goose")) + list((compiler.parent/"include").rglob("*.h"))
        for name in ("source.json", "toolchain.json"):
            path = compiler.parent.parent/name
            if path.is_file():
                paths.append(path)
        source_metadata = compiler.parent.parent/"source.json"
        if source_metadata.is_file():
            source = json.loads(source_metadata.read_text()); self.report["compiler_build"] = source
            for category, subdirectory in (("headers", "compiler"), ("patches", "")):
                for name, expected in source.get(category, {}).items():
                    matches = [path for path in (compiler.parent.parent/subdirectory/name, ROOT/subdirectory/name)
                               if path.is_file() and arena.sha256(path) == expected]
                    if not matches:
                        raise ValueError(f"compiler {category} input differs from source.json: {name}")
                    paths.append(matches[0])
        for case in self.workloads:
            paths += list(Path(case["source"]).parent.glob("*.goose"))
            paths += [Path(value) for value in case["source_files"]]
        if "wasmtime" in self.args.engines:
            path = Path(self.tools["host"]).with_suffix(".json")
            host = json.loads(path.read_text()); self.report["host_build"] = host
            if arena.sha256(Path(self.tools["host"])) != host["host_sha256"]:
                raise ValueError("Wasmtime host binary does not match its build metadata")
            if arena.sha256(Path(host["library"])) != host["library_sha256"]:
                raise ValueError("Wasmtime library does not match host metadata")
            paths += [path, Path(host["library"])]
        for path in sorted(set(paths)):
            self.pin(path)

    def verify(self):
        for path, expected in self.report["inputs"].items():
            if not Path(path).is_file() or arena.sha256(Path(path)) != expected:
                raise ValueError(f"pinned input/artifact changed: {path}")
        environment = self.report.get("environment", {})
        for key, value in environment.get("host_controls", {}).items():
            if os.environ.get(key) != value:
                raise ValueError(f"environment changed: {key}")
        if self.args.cpu is None and "cpu_affinity" in environment:
            if sorted(os.sched_getaffinity(0)) != environment["cpu_affinity"]:
                raise ValueError("inherited runtime CPU affinity changed")

    def execute(self, command, name, *, stdin=""):
        base = self.output / name; attempt = 0
        directory = base / f"attempt-{attempt:02}"
        while directory.exists():
            attempt += 1; directory = base / f"attempt-{attempt:02}"
        result = arena.execute(command, directory, cwd=ROOT, stdin=stdin, timeout=self.args.timeout)
        row = {key: result[key] for key in ("command", "cwd", "returncode", "wall_seconds", "error")}
        row["log_directory"] = str(directory)
        self.report["commands"].append(row); self.save()
        return result, str(directory)

    def metadata(self):
        info = {"platform": platform.platform(), "python": sys.version, "cpu_count": os.cpu_count(),
                "selected_runtime_cpu": self.args.cpu,
                "tools": {}, "host_controls": {key: os.environ.get(key) for key in
                ("PATH", "EM_NODE_JS", "EM_CONFIG", "EM_CACHE", "EMCC_CORES", "TMPDIR", "GOOSE_STDLIB",
                 "LD_PRELOAD", "LD_LIBRARY_PATH", "NODE_OPTIONS", "RAYON_NUM_THREADS", "OMP_NUM_THREADS")}}
        if hasattr(os, "sched_getaffinity"):
            info["cpu_affinity"] = sorted(os.sched_getaffinity(0))
        if Path("/proc/cpuinfo").is_file():
            info["cpuinfo"] = Path("/proc/cpuinfo").read_text()
        self.report["environment"] = info
        for name, executable in self.tools.items():
            command = [executable, "--version"]
            if name == "node":
                command = [executable, "-p", "JSON.stringify(process.versions)"]
            result, directory = self.execute(command, f"metadata/{name}")
            info["tools"][name] = {"command": command, "output": result["stdout"]+result["stderr"],
                                    "returncode": result["returncode"], "log_directory": directory}
        for compiler in ("gcc", "clang"):
            for march in ("generic", "native"):
                flags = self.arch_flags(march)
                command = [self.tools[compiler], *flags, "-Q", "--help=target"]
                if compiler == "clang":
                    command = [self.tools[compiler], *flags, "-###", "-x", "c", "-c", os.devnull, "-o", os.devnull]
                self.execute(command, f"metadata/{compiler}-{march}-target")

    def arch_flags(self, march):
        if march == "native":
            return ["-march=native"]
        return [f"-march={self.args.generic_march}", f"-mtune={self.args.generic_mtune}"]

    def flags(self, variant):
        result = [f"-O{variant['optimization']}", *COMMON]
        if variant["family"] == "native":
            return result + self.arch_flags(variant["march"])
        result += ["-m64", "-fwasm-exceptions", "-mno-relaxed-simd"]
        if variant["simd"] == "simd128":
            result.append("-msimd128")
        else:
            result.append("-mno-simd128")
        return result

    def failure(self, phase, error, **context):
        self.report["failures"].append({"phase": phase, "error": str(error), **context})

    def build(self):
        compiler = self.tools["goose"]; headers = str(Path(compiler).parent/"include")
        if not (Path(headers)/"goose.h").is_file():
            raise ValueError("installed Goose include/goose.h is required")
        host_objects = {}
        for variant in self.variants:
            if variant["family"] in ("direct", "wasm-opt"):
                continue
            compiler_name = "emcc"
            if variant["family"] == "native":
                compiler_name = variant["compiler"]
            path = self.output/"build/host"/(variant["id"]+".o"); path.parent.mkdir(parents=True, exist_ok=True)
            result, _ = self.execute([self.tools[compiler_name], *self.flags(variant), "-c", ROOT/"bench/host_input.c", "-o", path],
                                     f"build-logs/host/{variant['id']}")
            host_objects[variant["id"]] = None
            if not result["returncode"] and path.is_file():
                self.pin(path); host_objects[variant["id"]] = path
        for case in self.workloads:
            directory = self.output/"build"/case["id"]; directory.mkdir(parents=True, exist_ok=True)
            generated = {}
            for target in ("native", "wasm"):
                path = directory/(target+".c")
                command = [compiler, case["source"], "--target", target, "--standalone", "--offline", "-O2", "-o", path]
                if target == "wasm":
                    command += ["--stack-reserve", "16777216"]
                result, _ = self.execute(command, f"build-logs/{case['id']}/frontend-{target}")
                if not result["returncode"] and path.is_file():
                    self.pin(path); generated[target] = path
            for variant in self.variants:
                key = case["id"]+"/"+variant["id"]
                if self.report["artifacts"].get(key, {}).get("status") == "built":
                    continue
                suffix = ".wasm"
                if variant["family"] == "native":
                    suffix = ".bin"
                path = directory/(variant["id"]+suffix)
                row = {"task": case["name"], "task_id": case["id"], "variant": variant["id"],
                       "family": variant["family"], "path": str(path), "status": "failed"}
                self.report["artifacts"][key] = row
                command = None
                if variant["family"] == "direct":
                    deps = directory/"direct-dependencies.json"
                    command = [compiler, case["source"], "--target", "wasm-direct", "--offline", "-O2",
                               "--wasm-initial-pages", str(self.args.initial_pages), "--wasm-max-pages", str(self.args.maximum_pages),
                               "--wasm-stats", directory/"direct-stats.json", "--wasm-deps", deps, "-o", path]
                elif variant["family"] == "wasm-opt":
                    source = self.report["artifacts"].get(case["id"]+"/direct-O2", {})
                    if source.get("status") == "built":
                        command = [self.tools["wasm_opt"], source["path"], "-O3", "--enable-bulk-memory",
                                   "--enable-sign-ext", "--enable-multivalue", "--enable-nontrapping-float-to-int",
                                   "--enable-simd", "-o", path]
                        row.update(input_wasm=source["path"], input_wasm_sha256=source["sha256"])
                elif variant["family"] == "native" and "native" in generated and host_objects[variant["id"]]:
                    command = [self.tools[variant["compiler"]], generated["native"], *self.flags(variant), "-I", headers,
                               host_objects[variant["id"]], "-lm", "-pthread", "-ldl", "-o", path]
                elif variant["family"] == "c-wasm" and "wasm" in generated and host_objects[variant["id"]]:
                    command = [self.tools["emcc"], generated["wasm"], *self.flags(variant), "-I", headers,
                        "-sALLOW_MEMORY_GROWTH=1", "-sINITIAL_MEMORY=33554432", "-sMAXIMUM_MEMORY=2147483648",
                        "-sSTACK_SIZE=4194304", "-sSTACK_OVERFLOW_CHECK=2", "-sASSERTIONS=1", "-sERROR_ON_UNDEFINED_SYMBOLS=1",
                        "-sSTANDALONE_WASM=1", "-sSUPPORT_LONGJMP=wasm", "-sWASM_LEGACY_EXCEPTIONS=0",
                        host_objects[variant["id"]], "-o", path]
                try:
                    if command is None:
                        raise ValueError("required generated C or separate host object failed")
                    result, logs = self.execute(command, f"build-logs/{key}/artifact")
                    row["artifact_build_wall_seconds"] = result["wall_seconds"]
                    if variant["family"] == "wasm-opt":
                        row["postprocess_wall_seconds"] = result["wall_seconds"]
                    if result["returncode"] or not path.is_file():
                        raise ValueError(f"build failed: {logs}")
                    if variant["family"] != "native":
                        expected = 32
                        if variant["family"] == "c-wasm":
                            expected = 64
                        if wasm_memories(path) != [expected]:
                            raise ValueError(f"expected one memory{expected}")
                    self.pin(path); row.update(status="built", sha256=arena.sha256(path), bytes=path.stat().st_size)
                    if variant["family"] in ("native", "c-wasm"):
                        row["generated_c"] = str(generated["wasm"])
                        if variant["family"] == "native":
                            row["generated_c"] = str(generated["native"])
                        row["generated_c_sha256"] = arena.sha256(Path(row["generated_c"]))
                    if variant["family"] == "direct":
                        for dependency in json.loads(deps.read_text()):
                            if dependency.get("kind", "source") == "source" and Path(dependency["path"]).is_file():
                                self.pin(Path(dependency["path"]))
                    if variant["family"] != "native" and "wasmtime" in self.args.engines and self.args.wasmtime_mode == "precompiled":
                        aot = path.with_suffix(".cwasm")
                        result, logs = self.execute([self.tools["host"], "--compile", path, aot], f"build-logs/{key}/preparation")
                        row["preparation_wall_seconds"] = result["wall_seconds"]
                        if result["returncode"] or result["stdout"] or result["stderr"] or not aot.is_file():
                            raise ValueError(f"AOT preparation failed: {logs}")
                        self.pin(aot); row.update(aot_path=str(aot), aot_sha256=arena.sha256(aot))
                except (OSError, ValueError) as error:
                    row["status"] = "failed"; row["error"] = str(error)
                    self.failure("build", error, task=case["name"], variant=variant["id"])
                self.save()

    def cells(self):
        cells = []
        for case in self.workloads:
            for variant in self.variants:
                engines = self.args.engines
                if variant["family"] == "native":
                    engines = ["native"]
                cells += [(case, variant["id"], engine) for engine in engines]
        return cells

    def run_cell(self, case, variant, engine, phase, round_):
        for row in self.report["observations"]:
            if (row["task"], row["variant"], row["engine"], row["phase"], row["round"]) == (case["name"], variant, engine, phase, round_):
                return row
        artifact = self.report["artifacts"][case["id"]+"/"+variant]
        row = {"task": case["name"], "variant": variant, "engine": engine, "phase": phase,
               "round": round_, "status": "failed"}
        try:
            allowed = None
            if hasattr(os, "sched_getaffinity"):
                allowed = sorted(os.sched_getaffinity(0))
            effective = allowed
            if self.args.cpu is not None:
                effective = [self.args.cpu]
            row.update(allowed_affinity_before_launch=allowed, runtime_affinity=effective)
            phases = self.report.setdefault("runtime_phase_affinity", {})
            if phase in phases and phases[phase] != effective:
                raise ValueError("effective runtime affinity changed within phase")
            if phase == "confirm" and "pilot" in phases and phases["pilot"] != effective:
                raise ValueError("confirmation runtime affinity differs from pilot")
            phases[phase] = effective
            if artifact["status"] != "built":
                raise ValueError("artifact build/preparation failed")
            command = [artifact["path"]]
            if engine == "v8":
                command = [self.tools["node"], ROOT/"scripts/run_wasm.mjs", artifact["path"]]
            if engine == "wasmtime":
                command = [self.tools["host"], artifact["path"]]
                if self.args.wasmtime_mode == "precompiled":
                    command = [self.tools["host"], "--precompiled", artifact["aot_path"]]
            if self.args.cpu is not None:
                command = [self.tools["taskset"], "-c", str(self.args.cpu), *command]
            profile = "run"
            if phase == "qualify":
                profile = "test"
            config = case[profile]
            result, logs = self.execute(command, f"runtime/{phase}/{round_:02}/{case['id']}/{variant}/{engine}", stdin=config["stdin"])
            row.update(log_directory=logs, wall_seconds=result["wall_seconds"])
            if result["stderr"] or result["error"]:
                raise ValueError(f"runtime diagnostics: {logs}")
            row.update(arena.parse_port_result(result["stdout"], result["returncode"], config["checksum"]))
            if row["timed_region_seconds"] > row["wall_seconds"]:
                raise ValueError("internal timed region exceeds enclosing process wall time")
            row.update(status="passed", profile=profile, artifact_sha256=artifact["sha256"])
        except (OSError, ValueError, KeyError) as error:
            row["error"] = str(error); self.failure(phase, error, task=case["name"], variant=variant, engine=engine, round=round_)
        self.report["observations"].append(row); self.save()
        return row

    def qualify(self):
        cells = self.cells(); random.Random(self.args.seed).shuffle(cells)
        for case, variant, engine in cells:
            self.run_cell(case, variant, engine, "qualify", 0)

    def qualified(self, case, variant, engine):
        return any(row["phase"] == "qualify" and row["status"] == "passed" and
                   (row["task"], row["variant"], row["engine"]) == (case["name"], variant, engine)
                   for row in self.report["observations"])

    def rounds(self, phase, cells, count):
        rng = random.Random(self.args.seed + STAGES.index(phase))
        for round_ in range(count):
            tasks = list(self.workloads); rng.shuffle(tasks)
            for task in tasks:
                block = [cell for cell in cells if cell[0]["name"] == task["name"]]; rng.shuffle(block)
                for case, variant, engine in block:
                    self.run_cell(case, variant, engine, phase, round_)

    def pilot(self):
        cells = [cell for cell in self.cells() if self.qualified(*cell)]
        self.rounds("pilot", cells, self.args.pilot_samples)
        for case in self.workloads:
            rows = [row for row in self.report["observations"] if row["task"] == case["name"] and row["phase"] == "pilot"]
            native = [row["id"] for row in self.variants if row["family"] == "native"]
            wasm = [row["id"] for row in self.variants if row["family"] in ("direct", "c-wasm", "wasm-opt")]
            selected = {"native": pick_reference([row for row in rows if row["engine"] == "native"], native, self.args.pilot_samples), "wasm": {}}
            for engine in self.args.engines:
                selected["wasm"][engine] = pick_reference([row for row in rows if row["engine"] == engine], wasm, self.args.pilot_samples)
                if selected["wasm"][engine] is not None:
                    chosen = selected["wasm"][engine]
                    chosen["family"] = next(row["family"] for row in self.variants if row["id"] == chosen["variant"])
                    chosen["self_reference"] = chosen["variant"] == "direct-O2"
            if selected["native"] is None or any(value is None for value in selected["wasm"].values()):
                self.failure("pilot", "no complete qualified reference", task=case["name"])
            self.report["selection"][case["name"]] = selected
        self.save()

    def confirm(self):
        cells = []
        for case in self.workloads:
            selection = self.report["selection"].get(case["name"], {})
            native = selection.get("native")
            if native is None or not self.qualified(case, ANCHOR, "native"):
                self.failure("confirm", "missing selected native or GCC-O2-generic anchor", task=case["name"]); continue
            block = [(case, variant, "native") for variant in sorted({ANCHOR, native["variant"]})]
            for engine in self.args.engines:
                wasm = selection.get("wasm", {}).get(engine)
                if wasm is None or not self.qualified(case, "direct-O2", engine):
                    self.failure("confirm", "missing direct or selected Wasm cell", task=case["name"], engine=engine); continue
                block += [(case, "direct-O2", engine), (case, wasm["variant"], engine)]
            unique = {(variant, engine): (case, variant, engine) for case, variant, engine in block}
            cells += list(unique.values())
        self.rounds("confirm", cells, self.args.samples)

    def run(self):
        stages = self.args.stages
        if "all" in stages:
            stages = STAGES
        for stage in STAGES:
            if stage not in stages:
                continue
            self.verify()
            index = STAGES.index(stage)
            if index and self.report["phases"].get(STAGES[index-1]) != "complete":
                raise ValueError(f"{stage} requires completed {STAGES[index-1]} stage")
            if self.report["phases"].get(stage) == "complete":
                continue
            metadata = {"started_utc": arena.utc_now()}
            if hasattr(os, "getloadavg"):
                metadata["start_load_average"] = list(os.getloadavg())
            self.report["phase_metadata"].setdefault(stage, []).append(metadata); self.save()
            try:
                getattr(self, stage)(); self.verify()
            finally:
                metadata["ended_utc"] = arena.utc_now()
                if hasattr(os, "getloadavg"):
                    metadata["end_load_average"] = list(os.getloadavg())
                self.save()
            self.report["phases"][stage] = "complete"; self.save()
        self.report["status"] = "incomplete"
        if self.report["phases"].get("confirm") == "complete":
            self.report["status"] = "passed"
            if self.args.smoke:
                self.report["status"] = "passed-smoke"
        if self.report["failures"]:
            self.report["status"] = "failed"
        self.report["updated_utc"] = arena.utc_now(); self.save()
        print(self.report["status"], self.output/"report.json")
        return int(bool(self.report["failures"]))


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    result.add_argument("--output-dir", type=Path, required=True)
    result.add_argument("--cases", type=Path, action="append", default=[])
    result.add_argument("--no-langarena", action="store_true")
    result.add_argument("--filter", action="append", default=[])
    result.add_argument("--stages", "--stage", nargs="+", choices=(*STAGES, "all"), default=["all"])
    result.add_argument("--samples", type=int, default=9)
    result.add_argument("--pilot-samples", type=int, default=3)
    result.add_argument("--smoke", action="store_true", help="allow reduced rounds; correctness evidence only")
    result.add_argument("--plan", action="store_true", help="print workload/matrix counts without tool execution")
    result.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["wasmtime"])
    result.add_argument("--native-compilers", nargs="+", choices=("gcc", "clang"), default=["gcc", "clang"])
    result.add_argument("--native-levels", nargs="+", type=int, choices=(2,3), default=[2,3])
    result.add_argument("--march", nargs="+", choices=("generic", "native"), default=["generic", "native"])
    result.add_argument("--c-wasm-levels", nargs="+", type=int, choices=(2,3), default=[2,3])
    result.add_argument("--simd", nargs="+", choices=("scalar", "simd128"), default=["scalar", "simd128"])
    result.add_argument("--generic-march", default="x86-64")
    result.add_argument("--generic-mtune", default="generic")
    result.add_argument("--goose", type=Path, default=ROOT/"build/bin/goose")
    result.add_argument("--host", type=Path, default=ROOT/"build/bin/goose-wasmtime")
    result.add_argument("--cc", default="gcc")
    result.add_argument("--clang", default="clang-23")
    result.add_argument("--emcc", default="emcc")
    result.add_argument("--node", default="node")
    result.add_argument("--wasmtime-mode", choices=("precompiled", "wasm"), default="precompiled")
    result.add_argument("--wasm-opt", type=Path, help="optional normal-semantics -O3 direct-Wasm postprocess reference")
    result.add_argument("--cpu", type=int, help="pin runtime children only; builds and AOT preparation retain inherited affinity")
    result.add_argument("--initial-pages", type=int, default=16)
    result.add_argument("--maximum-pages", type=int, default=256)
    result.add_argument("--seed", type=int, default=924371)
    result.add_argument("--timeout", type=float, default=600)
    return result


def main():
    options = parser(); args = options.parse_args()
    if args.samples < 1 or args.pilot_samples < 1 or args.timeout <= 0:
        options.error("sample counts and timeout must be positive")
    if not args.smoke and (args.samples < 9 or args.pilot_samples < 3):
        options.error("references require >=3 pilot and >=9 fresh confirmation rounds; use --smoke for correctness only")
    if args.plan:
        workloads = load_workloads(args); matrix = variants(args)
        cells = sum(len(args.engines) for row in matrix if row["family"] != "native")
        cells += sum(row["family"] == "native" for row in matrix)
        print(json.dumps({"workloads": workloads, "variants": matrix, "qualification_cells": len(workloads)*cells,
                          "pilot_observations": len(workloads)*cells*args.pilot_samples,
                          "maximum_confirmation_observations": len(workloads)*(2+2*len(args.engines))*args.samples}, indent=2))
        return 0
    try:
        return Harness(args).run()
    except (OSError, ValueError, KeyError) as error:
        print(f"runtime-reference: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
