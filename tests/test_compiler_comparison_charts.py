#!/usr/bin/env python3
"""Chart receipts require raw invocation, artifact and independent-output proof."""
import copy
import importlib.util
import itertools
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bench"))
SPEC = importlib.util.spec_from_file_location("compiler_comparison_charts", ROOT / "bench/compiler_comparison_charts.py")
CHARTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHARTS)


class CompilerComparisonCharts(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.source = self.path / "program.goose"
        self.source.write_text("fn main() { print(42); }\n")
        self.golden = self.path / "expected.out"
        self.golden.write_text("42\n")
        compiler = self.path / "compiler"
        compiler.write_text("synthetic compiler identity")
        cases = [dict(name=name, source=str(self.source), source_sha256=CHARTS.bench.cold.sha256(self.source),
                      expected_path=str(self.golden), expected_sha256=CHARTS.bench.cold.sha256(self.golden), stdin="")
                 for name in CHARTS.LABELS]
        self.report = dict(schema="goose-compiler-comparison-v1", status="failed", samples=1,
            inputs_unchanged=True, artifacts_unchanged=True, workloads=cases, builds=[], validations={},
            compilers={name: dict(path=str(compiler), sha256=CHARTS.bench.cold.sha256(compiler)) for name in CHARTS.bench.COMPILERS},
            configuration=dict(cpu="7", node="node", cc="gcc", stdlib=str(ROOT / "stdlib")))
        for name, case, target in itertools.product(CHARTS.bench.COMPILERS, cases, CHARTS.bench.TARGETS):
            for sample in [-1, 0]:
                artifact = self.path / f"{name}-{case['name']}-{target}"
                cmd = CHARTS.bench.build_command(compiler, name, case, target, artifact, ROOT / "stdlib")
                self.report["builds"].append(dict(compiler=name, workload=case["name"], target=target,
                    round=sample, phase="warmup" if sample < 0 else "measurement", artifact=str(artifact),
                    command=["taskset", "-c", "7", *map(str, cmd)], status="failed", exit_code=1,
                    pid=123, wall_seconds=0.01, stdout="", stderr="unsupported"))
        artifact = self.path / "cpp-squares-wasm-direct"
        artifact.write_bytes(b"synthetic artifact")
        digest = CHARTS.bench.cold.sha256(artifact)
        key = ":".join(["wasm-direct", digest, CHARTS.bench.cold.sha256(self.golden)])
        for record in self.report["builds"][:2]:
            record.update(status="passed", exit_code=0, artifact_sha256=digest, validation_key=key, stderr="")
        proof = []
        for executable, script in [("node", "run_wasm.mjs"), (sys.executable, "run_wasmtime.py")]:
            proof.append(dict(command=["taskset", "-c", "7", executable, str(ROOT / "scripts" / script), str(artifact)],
                status="passed", exit_code=0, pid=456, wall_seconds=0.02, stdout="42\n", stderr="", stdin=""))
        self.report["validations"][key] = dict(status="passed", commands=proof)
        self.report["summary"] = CHARTS.bench.summaries(self.report)

    def test_failed_cells_are_retained_without_zero_scores(self):
        rows = CHARTS.checked_rows(self.report)
        self.assertEqual(len(rows), 66)
        self.assertEqual(sum(row["qualified"] for row in rows.values()), 1)
        self.assertTrue(all(row["compile_wall_seconds"] is None for row in rows.values() if not row["qualified"]))

    def test_tampered_summary_invocation_output_and_artifact_are_rejected(self):
        for mutation in ["summary", "invocation", "output", "artifact"]:
            report = copy.deepcopy(self.report)
            if mutation == "summary":
                report["summary"][0]["compile_wall_seconds"]["median"] = 0
            elif mutation == "invocation":
                report["builds"][0]["command"][3] = "another-compiler"
            elif mutation == "output":
                next(iter(report["validations"].values()))["commands"][0]["stdout"] = "43\n"
            else:
                report["builds"][0]["artifact_sha256"] = "0" * 64
            with self.assertRaises(ValueError, msg=mutation):
                CHARTS.checked_rows(report)

    def test_plot_receipt_uses_null_for_unavailable_cells(self):
        rows = CHARTS.checked_rows(self.report)
        fig, ax = CHARTS.plt.subplots()
        self.addCleanup(CHARTS.plt.close, fig)
        values = CHARTS.panel(ax, list(CHARTS.LABELS), "wasm-direct", rows)
        self.assertEqual(len(ax.patches), 1)
        self.assertEqual(sum(value["median_ms"] is None for value in values), 32)
        self.assertEqual(len([label for label in ax.texts if label.get_text() == "unavailable"]), 32)


if __name__ == "__main__":
    unittest.main()
