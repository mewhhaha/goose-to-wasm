#!/usr/bin/env python3
"""Check reference selection, protocol scope, pairing and runtime isolation."""
import json
import math
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"bench"))
import runtime_reference as reference


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


if __name__ == "__main__":
    unittest.main()
