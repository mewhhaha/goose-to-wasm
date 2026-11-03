#!/usr/bin/env python3
"""Check reference selection, protocol scope, pairing and runtime isolation."""
import json
import math
from copy import deepcopy
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"bench"))
import runtime_reference as reference
import runtime_reference_charts as charts


class RuntimeReference(unittest.TestCase):
    def test_default_matrix_and_anchor(self):
        args = reference.parser().parse_args(["--output-dir", "unused"])
        matrix = reference.variants(args)
        self.assertEqual(len(matrix),13)
        self.assertEqual(sum(row["family"] == "native" for row in matrix),8)
        self.assertEqual(sum(row["family"] == "c-wasm" for row in matrix),4)
        self.assertEqual(len(reference.load_workloads(args)),7)
        args.native_compilers = ["clang"]; args.native_levels = [3]; args.march = ["native"]
        args.wasm_opt = Path("optimizer")
        matrix = reference.variants(args)
        self.assertEqual(sum(row["id"] == reference.ANCHOR for row in matrix),1)
        self.assertEqual(sum(row["family"] == "wasm-opt" for row in matrix),1)

    def test_custom_manifest_paths_protocol_and_metadata(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name); source = directory/"kernel.goose"; source.write_text("fn main() {}")
            config = {"schema":"goose-runtime-reference-cases-v1","cases":[{
                "name":"Example::Kernel","source":"kernel.goose","source_files":["producer.py"],
                "test":{"stdin":"1 2\n","checksum":3},"run":{"stdin":"5 8\n","checksum":13},
                "notes":"Kernel adapter, not full-program timing"}]}
            manifest = directory/"cases.json"; manifest.write_text(json.dumps(config))
            args = SimpleNamespace(no_langarena=True,cases=[manifest],filter=[])
            case = reference.load_workloads(args)[0]
            self.assertEqual(case["source"],str(source))
            self.assertEqual(case["id"],"example_kernel")
            self.assertEqual(case["metadata"]["notes"],config["cases"][0]["notes"])
            self.assertIn(str(directory/"producer.py"),case["source_files"])
            config["cases"][0]["test"]["checksum"] = True
            manifest.write_text(json.dumps(config))
            with self.assertRaises(ValueError): reference.load_workloads(args)

    def test_pilot_requires_all_successful_rounds_and_penalizes_variation(self):
        rows = []
        for variant, values in (("variable",[1,2,3]),("stable",[2.5]*3),("failed",[.1,.1])):
            rows += [{"variant":variant,"status":"passed","timed_region_seconds":value} for value in values]
        self.assertEqual(reference.pick_reference(rows,["variable","stable","failed"],3)["variant"],"stable")
        self.assertIsNone(reference.pick_reference(rows,["failed"],3))

    def test_pilot_does_not_select_on_confirmation(self):
        harness = reference.Harness.__new__(reference.Harness)
        case = {"name":"task"}; harness.workloads = [case]
        harness.args = SimpleNamespace(pilot_samples=3,engines=["wasmtime"])
        harness.variants = [{"id":name,"family":family} for name,family in
                            (("a","native"),("b","native"),("wasm","c-wasm"))]
        rows = []
        for phase, variant, value, engine in (("pilot","a",1,"native"),("pilot","b",2,"native"),
                                               ("pilot","wasm",3,"wasmtime"),("confirm","b",.01,"native")):
            rows += [{"task":"task","phase":phase,"variant":variant,"engine":engine,"status":"passed",
                      "timed_region_seconds":value,"round":round_} for round_ in range(3)]
        harness.report = {"observations":rows,"selection":{},"failures":[]}
        harness.cells = lambda: []; harness.rounds = lambda *args: None; harness.save = lambda: None
        harness.pilot()
        self.assertEqual(harness.report["selection"]["task"]["native"]["variant"],"a")

    def test_paired_geometric_ratios_require_the_full_selected_suite(self):
        report = {"configuration":{"engines":["wasmtime"],"samples":2},
                  "workloads":[{"name":"a"},{"name":"b"}],"observations":[],"selection":{}}
        for task, direct, native, anchor, wasm in (("a",8,2,4,4),("b",18,9,9,6)):
            report["selection"][task] = {"native":{"variant":"chosen"},"wasm":{"wasmtime":{"variant":"wasm"}}}
            for round_ in range(2):
                for variant, engine, value in (("direct-O2","wasmtime",direct),("chosen","native",native),
                                                (reference.ANCHOR,"native",anchor),("wasm","wasmtime",wasm)):
                    report["observations"].append({"task":task,"variant":variant,"engine":engine,"round":round_,
                        "phase":"confirm","status":"passed","timed_region_seconds":value*(round_+1),"wall_seconds":100})
        reference.derive_summaries(report)
        ratio = next(row for row in report["geometric_ratios"] if row["comparison"] == "selected_native")
        self.assertAlmostEqual(ratio["ratio"]["median"],math.sqrt(8))
        report["observations"] = [row for row in report["observations"] if not
                                  (row["task"] == "b" and row["variant"] == "direct-O2" and row["round"] == 1)]
        reference.derive_summaries(report)
        ratio = next(row for row in report["geometric_ratios"] if row["comparison"] == "selected_native")
        self.assertIsNone(ratio["per_round"][1]["geometric_direct_over_reference"])
        self.assertEqual(ratio["per_round"][1]["missing_tasks"],["b"])
        report["selection"]["b"] = {"native":None,"wasm":{"wasmtime":None}}
        reference.derive_summaries(report)  # Failed candidates remain reportable.

    def test_direct_baseline_can_win_and_confirmation_deduplicates(self):
        harness = reference.Harness.__new__(reference.Harness)
        case = {"name":"task"}; harness.workloads = [case]
        harness.args = SimpleNamespace(pilot_samples=3,samples=9,engines=["wasmtime"])
        harness.variants = [{"id":name,"family":family} for name,family in
                            ((reference.ANCHOR,"native"),("direct-O2","direct"),("wasm","c-wasm"))]
        rows = []
        for variant,value,engine in ((reference.ANCHOR,.5,"native"),("direct-O2",1,"wasmtime"),("wasm",2,"wasmtime")):
            rows += [{"task":"task","phase":"pilot","variant":variant,"engine":engine,"status":"passed",
                      "timed_region_seconds":value,"round":round_} for round_ in range(3)]
        harness.report = {"observations":rows,"selection":{},"failures":[]}
        harness.cells = lambda: []; harness.rounds = lambda *args: None; harness.save = lambda: None
        harness.qualified = lambda *args: True
        harness.pilot()
        chosen = harness.report["selection"]["task"]["wasm"]["wasmtime"]
        self.assertTrue(chosen["self_reference"])
        seen = []; harness.rounds = lambda phase,cells,count: seen.extend(cells)
        harness.confirm()
        self.assertEqual({(variant,engine) for _,variant,engine in seen},
                         {(reference.ANCHOR,"native"),("direct-O2","wasmtime")})
        self.assertEqual(len(seen),2)

    def test_actual_memory_address_width_is_checked(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name)/"module.wasm"
            for flags, expected in ((0,32),(4,64)):
                path.write_bytes(b"\0asm\x01\0\0\0"+bytes([5,3,1,flags,1]))
                self.assertEqual(reference.wasm_memories(path),[expected])
            path.write_bytes(b"\0asm\x01\0\0\0\x05\x80")
            with self.assertRaises(ValueError): reference.wasm_memories(path)

    def test_optimizer_command_retains_standard_simd_and_memory_width(self):
        import wasmtime
        with tempfile.TemporaryDirectory() as name:
            directory=Path(name); compiler=directory/"bin/goose"
            (compiler.parent/"include").mkdir(parents=True)
            (compiler.parent/"include/goose.h").write_text("")
            raw=directory/"simd.wasm"
            raw.write_bytes(wasmtime.wat2wasm('''(module (memory 1)
              (func (export "run") (result i32)
                (i32x4.extract_lane 0 (v128.const i32x4 1 2 3 4))))'''))
            harness=reference.Harness.__new__(reference.Harness)
            harness.output=directory; harness.tools={"goose":str(compiler),"wasm_opt":"optimizer"}
            harness.args=SimpleNamespace(engines=[])
            harness.workloads=[{"id":"simd","name":"SIMD","source":"source.goose"}]
            harness.variants=[{"id":"optimized","family":"wasm-opt"}]
            harness.report={"artifacts":{"simd/direct-O2":{"status":"built","path":str(raw),
                              "sha256":reference.arena.sha256(raw)}},"failures":[]}
            seen=[]
            def execute(command, name):
                if command[0]=="optimizer":
                    seen.append(command)
                    self.assertIn("--enable-simd",command)
                    self.assertFalse({"--enable-relaxed-simd","--ignore-implicit-traps",
                                      "--traps-never-happen","--fast-math"}&set(map(str,command)))
                    Path(command[-1]).write_bytes(raw.read_bytes())
                return {"returncode":0,"stdout":"","stderr":"","wall_seconds":0.0},"log"
            harness.execute=execute; harness.pin=lambda path:None; harness.save=lambda:None
            harness.build()
            self.assertEqual(len(seen),1)
            artifact=harness.report["artifacts"]["simd/optimized"]
            self.assertEqual(artifact["status"],"built")
            self.assertEqual(reference.wasm_memories(Path(artifact["path"])),[32])
            self.assertEqual(artifact["input_wasm_sha256"],reference.arena.sha256(raw))

    def test_affinity_wraps_runtime_children_only(self):
        harness = reference.Harness.__new__(reference.Harness)
        harness.args = SimpleNamespace(cpu=3,wasmtime_mode="precompiled")
        harness.tools = {"taskset":"/taskset","host":"/host"}
        case = {"name":"task","id":"task","test":{"stdin":"input\n","checksum":7}}
        artifact = {"status":"built","path":"/raw.wasm","aot_path":"/aot.cwasm","sha256":"hash"}
        harness.report = {"artifacts":{"task/direct-O2":artifact},"observations":[],"failures":[]}
        commands = []
        def execute(command, name, *, stdin):
            commands.append((command,stdin))
            return {"stdout":"7\n100\n","stderr":"","returncode":0,"error":"","wall_seconds":1},"log"
        harness.execute = execute; harness.save = lambda: None
        self.assertEqual(harness.run_cell(case,"direct-O2","wasmtime","qualify",0)["status"],"passed")
        self.assertEqual(commands,[(["/taskset","-c","3","/host","--precompiled","/aot.cwasm"],"input\n")])
        self.assertEqual(harness.report["observations"][0]["runtime_affinity"],[3])
        harness.report["observations"] = []
        harness.execute = lambda *args, **kwargs: ({"stdout":"7\n2000000000\n","stderr":"", "returncode":0,
                                                   "error":"","wall_seconds":1},"log")
        row = harness.run_cell(case,"direct-O2","wasmtime","qualify",0)
        self.assertEqual(row["status"],"failed")
        self.assertIn("exceeds",row["error"])

    def test_frozen_compiler_headers_match_source_pins(self):
        for layout in ("frozen","active"):
            with tempfile.TemporaryDirectory() as name:
                root = Path(name); installed = root/"installed"; (installed/"bin").mkdir(parents=True)
                headers = installed/"compiler"
                if layout == "active": headers = root/"compiler"
                headers.mkdir()
                compiler = installed/"bin/goose"; compiler.write_text("compiler")
                header = headers/"example.h"; header.write_text("original")
                source_patch = root/"changes.patch"; source_patch.write_text("patch")
                source = {"headers":{"example.h":reference.arena.sha256(header)},
                          "patches":{"changes.patch":reference.arena.sha256(source_patch)}}
                (installed/"source.json").write_text(json.dumps(source)); (installed/"toolchain.json").write_text("{}")
                harness = reference.Harness.__new__(reference.Harness)
                harness.tools = {"goose":str(compiler)}; harness.workloads = []
                harness.args = SimpleNamespace(engines=[]); harness.report = {}
                paths = []; harness.pin = paths.append
                with patch.object(reference,"ROOT",root):
                    harness.pin_inputs()
                    self.assertIn(header,paths); self.assertIn(source_patch,paths)
                    self.assertIn(installed/"toolchain.json",paths)
                    header.write_text("changed")
                    with self.assertRaises(ValueError): harness.pin_inputs()


class NamedKernelChart(unittest.TestCase):
    def fixture(self):
        pins = {"reference.json":"reference-sha", "old-helper.py":"old-helper-sha",
                "host":"host-sha", "library":"library-sha", "baseline":"baseline-sha", "final":"final-sha"}
        host = {"version":"50.0.1", "host_sha256":"host-sha", "library":"library", "library_sha256":"library-sha"}
        frozen = {"schema":"goose-runtime-reference-v1", "status":"passed", "failures":[],
            "configuration":{"pilot_samples":3, "engines":["wasmtime"], "wasmtime_mode":"precompiled", "cpu":2},
            "workloads":[], "selection":{}, "artifacts":{}, "inputs":{"historical-helper.py":"old-helper-sha"},
            "host_build":host}
        report = {"schema":"goose-frozen-kernel-pairs-v1", "status":"passed", "failures":0, "coverage_exact":True,
            "configuration":{"samples":9, "references":True, "cpu":2, "reference":"reference.json",
                             "compilers":{"baseline":"baseline", "final":"final"}, "host":"host"},
            "compilers":{name:{"binary":name, "sha256":name+"-sha", "source":{"headers":{}, "patches":{}},
                                "resolved_source_inputs":{}} for name in ["baseline", "final"]},
            "workloads":frozen["workloads"], "selection":frozen["selection"], "host_build":host,
            "historical_input_resolution":{"historical-helper.py@old-helper-sha":"old-helper.py"},
            "artifacts":{}, "reference_roles":{}, "commands":[{"returncode":0, "error":""}], "observations":[]}
        def artifact(name, family):
            path = name+".bin"
            result = {"variant":name, "family":family, "path":path, "sha256":path+"-sha"}
            pins[path] = result["sha256"]
            if family != "native":
                result.update(aot_path=path+".aot", aot_sha256=path+".aot-sha")
                pins[result["aot_path"]] = result["aot_sha256"]
            return result
        for index, (task, _) in enumerate(item for _, group in charts.GROUPS for item in group):
            case = {"name":task, "id":str(index), "source":str(index)+".goose",
                    "test":{"stdin":"small\n", "checksum":17}, "run":{"stdin":"large\n", "checksum":34}}
            frozen["workloads"].append(case)
            native = "native-clang-O3-generic"
            wasm = "c-wasm-O3-simd128"
            if index == 0:
                native = "native-gcc-O2-generic"
                wasm = "direct-O2"
            frozen["selection"][task] = {"native":{"variant":native}, "wasm":{"wasmtime":{"variant":wasm}}}
            roles = {"original_direct":"direct-O2", "gcc_O2_anchor":"native-gcc-O2-generic",
                     "selected_native":native, "selected_wasm":wasm}
            report["reference_roles"][task] = {role:"ref--"+name for role, name in roles.items()}
            artifacts = {}
            for name in set(roles.values()):
                family = "direct"
                if name.startswith("native"):
                    family = "native"
                if name.startswith("c-wasm"):
                    family = "c-wasm"
                original = artifact(str(index)+"-"+name, family)
                original["variant"] = name
                frozen["artifacts"][str(index)+"/"+name] = original
                artifacts["ref--"+name] = deepcopy(original)
            for name in ["baseline", "final"]:
                artifacts[name] = artifact(str(index)+"-"+name, "direct")
                artifacts[name].update(variant=name, compiler_sha256=name+"-sha")
            report["artifacts"][task] = artifacts
            for phase, rounds, profile in [("qualify",1,"test"), ("measure",9,"run")]:
                for round_ in range(rounds):
                    for name, entry in artifacts.items():
                        elapsed = 3.0
                        if name == "final": elapsed = 2.0
                        if name == "baseline": elapsed = 4.0
                        if name == "ref--native-gcc-O2-generic": elapsed = 1.25
                        if name == "ref--native-clang-O3-generic": elapsed = 1.0
                        if name == "ref--c-wasm-O3-simd128": elapsed = 1.5
                        engine = "wasmtime"
                        if entry["family"] == "native": engine = "native"
                        report["observations"].append({"task":task, "variant":name, "phase":phase, "round":round_,
                            "profile":profile, "engine":engine, "runtime_affinity":[2],
                            "checksum":case[profile]["checksum"], "expected_checksum":case[profile]["checksum"],
                            "revision_exit":0, "artifact_sha256":entry["sha256"], "aot_sha256":entry.get("aot_sha256"),
                            "timed_region_seconds":elapsed*(round_+1), "process_wall_seconds":100.0})
        report.update(input_sha256=pins, input_sha256_after=deepcopy(pins), observations_expected=len(report["observations"]))
        return report, frozen, pins

    def test_named_overlay_uses_paired_intervals_and_deduplicated_references(self):
        report, frozen, pins = self.fixture()
        with patch.object(charts,"digest",side_effect=pins.__getitem__):
            table = charts.validate_kernels(report, frozen, "reference-sha", "final")
        self.assertEqual(len(table),10)
        self.assertTrue(table[0]["wasm_reference_is_baseline"])
        self.assertEqual(table[0]["relative_to_native"]["direct"]["median"],1.6)
        self.assertEqual(table[-1]["relative_to_native"]["direct"]["median"],2.0)
        self.assertAlmostEqual(table[-1]["direct_over_selected_wasm"]["median"],4/3)
        self.assertEqual(table[-1]["baseline_over_current"]["median"],1.5)
        self.assertEqual(table[-1]["relative_to_native"]["direct"]["mad"],0)

    def test_named_overlay_rejects_incomplete_or_mismatched_evidence(self):
        report, frozen, pins = self.fixture()
        cases = []
        changed = deepcopy(report); changed["observations"].pop(); cases.append(changed)
        changed = deepcopy(report); changed["observations"].append(changed["observations"][0]); cases.append(changed)
        for field, value in [("checksum",99), ("timed_region_seconds",float("nan")),
                             ("process_wall_seconds",.1), ("runtime_affinity",[3]), ("aot_sha256","wrong")]:
            changed = deepcopy(report); changed["observations"][0][field] = value; cases.append(changed)
        changed = deepcopy(report); changed["input_sha256_after"]["host"] = "wrong"; cases.append(changed)
        changed = deepcopy(report); changed["historical_input_resolution"].clear(); cases.append(changed)
        changed = deepcopy(report); changed["configuration"]["samples"] = 8; cases.append(changed)
        changed = deepcopy(report); changed["configuration"]["references"] = False; cases.append(changed)
        changed = deepcopy(report); changed["workloads"].pop(); cases.append(changed)
        changed = deepcopy(report); changed["host_build"]["library_sha256"] = "different-build"; cases.append(changed)
        changed = deepcopy(report); changed["compilers"]["final"]["sha256"] = "wrong"; cases.append(changed)
        with patch.object(charts,"digest",side_effect=pins.__getitem__):
            for index, changed in enumerate(cases):
                with self.subTest(index=index), self.assertRaises((AssertionError,KeyError)):
                    charts.validate_kernels(changed, frozen, "reference-sha", "final")


if __name__ == "__main__":
    unittest.main()
