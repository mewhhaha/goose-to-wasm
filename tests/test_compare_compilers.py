#!/usr/bin/env python3
"""Compilation comparison rows require complete builds and golden validations."""
import importlib.util
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bench"))
SPEC = importlib.util.spec_from_file_location("compare_compilers", ROOT / "bench/compare_compilers.py")
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)


class CompilerComparison(unittest.TestCase):
    def test_resource_usage_delta_reports_child_cpu_and_counters(self):
        before = SimpleNamespace(ru_utime=1.25, ru_stime=0.5, ru_majflt=2, ru_minflt=30,
                                 ru_nvcsw=4, ru_nivcsw=6, ru_inblock=8, ru_oublock=10)
        after = SimpleNamespace(ru_utime=1.75, ru_stime=0.7, ru_majflt=3, ru_minflt=41,
                                ru_nvcsw=7, ru_nivcsw=8, ru_inblock=12, ru_oublock=15)

        usage = BENCH.resource_usage_delta(before, after)
        self.assertAlmostEqual(usage["utime_seconds"], 0.5)
        self.assertAlmostEqual(usage["stime_seconds"], 0.2)
        self.assertAlmostEqual(usage["total_cpu_seconds"], 0.7)
        self.assertEqual({key: value for key, value in usage.items()
                          if not key.endswith("_seconds")}, dict(
            major_faults=1, minor_faults=11, voluntary_context_switches=3,
            involuntary_context_switches=2, block_input_operations=4,
            block_output_operations=5))

    def report(self):
        report = dict(samples=2, workloads=[dict(name="small")], builds=[],
                      validations={"proof": dict(status="passed")})
        for compiler in BENCH.COMPILERS:
            for target in BENCH.TARGETS:
                for sample in [-1, 0, 1]:
                    report["builds"].append(dict(compiler=compiler, workload="small", target=target,
                        phase="measurement" if sample >= 0 else "warmup", round=sample,
                        status="passed", validation_key="proof", wall_seconds=0.01))
        return report

    def test_complete_rows_and_stats(self):
        rows = BENCH.summaries(self.report())
        self.assertEqual(len(rows), 6)
        self.assertTrue(all(row["qualified"] for row in rows))
        self.assertTrue(all(row["compile_wall_seconds"]["n"] == 2 for row in rows))

    def test_order_comes_from_v2_or_legacy_report(self):
        report = self.report()
        report["compiler_order"] = ["cpp", "parent", "candidate"]
        self.assertEqual(BENCH.compiler_order(report), ("cpp", "parent", "candidate"))
        legacy = self.report()
        legacy["compilers"] = {"cpp": {}, "goose56": {}, "goose57": {}}
        for row in legacy["builds"]:
            if row["compiler"] == "parent":
                row["compiler"] = "goose56"
            elif row["compiler"] == "candidate":
                row["compiler"] = "goose57"
        self.assertEqual(BENCH.compiler_order(legacy), ("cpp", "goose56", "goose57"))
        self.assertEqual([row["compiler"] for row in BENCH.summaries(legacy)[:3]],
                         ["cpp", "cpp", "goose56"])

    def test_parent_binary_and_source_are_required(self):
        actions = {action.dest: action for action in BENCH.parser()._actions}
        self.assertTrue(actions["parent"].required)
        self.assertTrue(actions["parent_source"].required)
        self.assertEqual(actions["parent_label"].default, "Previous Goose")
        self.assertEqual(actions["candidate_label"].default, "Current Goose")

    def test_missing_failed_duplicate_and_unvalidated_samples_have_no_score(self):
        for mutation in ("missing", "failed", "duplicate", "unvalidated", "failed-validation", "warmup"):
            report = self.report()
            if mutation == "missing":
                report["builds"].pop(1)
            elif mutation == "failed":
                report["builds"][1]["status"] = "failed"
            elif mutation == "duplicate":
                report["builds"][2]["round"] = 0
            elif mutation == "unvalidated":
                report["builds"][1]["validation_key"] = "missing"
            elif mutation == "failed-validation":
                report["validations"]["proof"]["status"] = "failed"
            else:
                report["builds"][0]["status"] = "failed"
            rows = BENCH.summaries(report)
            self.assertEqual(len(rows), 6)
            self.assertFalse(rows[0]["qualified"], mutation)
            self.assertIsNone(rows[0]["compile_wall_seconds"], mutation)

    def test_no_successful_rows_are_fabricated_for_empty_report(self):
        report = self.report()
        report["builds"] = []
        self.assertTrue(all(not row["qualified"] and row["compile_wall_seconds"] is None
                            for row in BENCH.summaries(report)))

    def test_command_target_and_standalone_contract(self):
        for compiler in BENCH.COMPILERS:
            native = list(map(str, BENCH.build_command("compiler", compiler,
                dict(source="same.goose"), "native-c", "program.c", "same-stdlib")))
            self.assertEqual("--standalone" in native, compiler == "cpp")
            wasm = list(map(str, BENCH.build_command("compiler", compiler,
                dict(source="same.goose"), "wasm-direct", "program.wasm", "same-stdlib")))
            self.assertIn("--wasm-max-pages", wasm)
            self.assertNotIn("--standalone", wasm)

    def test_golden_contract_is_independent_and_strict(self):
        result = dict(status="passed", stdout="636\n42\n", stderr="", exit_code=0)
        self.assertTrue(BENCH.result_matches(result, dict(checksum=636)))
        for change in (dict(stdout="637\n42\n"), dict(stdout="636\n42\nnoise"),
                       dict(stderr="warning"), dict(status="failed"), dict(exit_code=1)):
            altered = {**result, **change}
            self.assertFalse(BENCH.result_matches(altered, dict(checksum=636)))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "golden.out"
            path.write_text("independent\n")
            self.assertFalse(BENCH.result_matches(result, dict(expected_path=str(path))))


if __name__ == "__main__":
    unittest.main()
