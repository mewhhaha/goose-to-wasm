#!/usr/bin/env python3
"""Chart receipts require raw invocation, artifact and independent-output proof."""
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bench"))
SPEC = importlib.util.spec_from_file_location("compiler_comparison_charts", ROOT / "bench/compiler_comparison_charts.py")
CHARTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHARTS)

GOOSE_LABELS = {"parent": "Experiment Parent", "candidate": "Experiment Candidate"}
V2_LABELS = {"cpp": "Previous C++", "parent": "Goose 58", "candidate": "Goose 59"}


class CompilerComparisonCharts(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.source = self.path / "program.goose"
        self.source.write_text("fn main() { print(42); }\n")
        self.golden = self.path / "expected.out"
        self.golden.write_text("42\n")
        self.report = self.build_report(CHARTS.V3, GOOSE_LABELS)

    def build_report(self, schema, labels):
        """Every cell fails except the first compiler's first Wasm warmup and measurement."""
        sha256 = CHARTS.bench.cold.sha256
        compilers = {}
        for name in labels:
            compiler = self.path / f"{name}-compiler"
            compiler.write_text(f"synthetic {name} compiler identity")
            compilers[name] = dict(path=str(compiler), sha256=sha256(compiler))
        cases = [dict(name=name, source=str(self.source), source_sha256=sha256(self.source),
                      expected_path=str(self.golden), expected_sha256=sha256(self.golden), stdin="")
                 for name in CHARTS.LABELS]
        report = dict(schema=schema, status="failed", samples=1, method="synthetic",
            inputs_unchanged=True, artifacts_unchanged=True, workloads=cases, builds=[], validations={},
            compiler_order=list(labels), compiler_labels=dict(labels), compilers=compilers,
            configuration=dict(cpu="7", node="node", cc="gcc", stdlib=str(ROOT / "stdlib")))
        for name, case, target in itertools.product(labels, cases, CHARTS.bench.TARGETS):
            for sample in [-1, 0]:
                artifact = self.path / f"{name}-{case['name']}-{target}"
                cmd = CHARTS.bench.build_command(compilers[name]["path"], case, target, artifact, ROOT / "stdlib")
                if name == "cpp" and target == "native-c":
                    cmd.insert(-2, "--standalone")  # as dated reports invoked the earlier C++ compiler
                report["builds"].append(dict(compiler=name, workload=case["name"], target=target,
                    round=sample, phase="warmup" if sample < 0 else "measurement", artifact=str(artifact),
                    command=["taskset", "-c", "7", *map(str, cmd)], status="failed", exit_code=1,
                    pid=123, wall_seconds=0.01, stdout="", stderr="unsupported"))
        artifact = Path(report["builds"][0]["artifact"])
        artifact.write_bytes(b"synthetic artifact")
        digest = sha256(artifact)
        key = ":".join(["wasm-direct", digest, sha256(self.golden)])
        for record in report["builds"][:2]:
            record.update(status="passed", exit_code=0, artifact_sha256=digest, validation_key=key, stderr="")
        proof = []
        for executable, script in [("node", "run_wasm.mjs"), (sys.executable, "run_wasmtime.py")]:
            proof.append(dict(command=["taskset", "-c", "7", executable, str(ROOT / "scripts" / script), str(artifact)],
                status="passed", exit_code=0, pid=456, wall_seconds=0.02, stdout="42\n", stderr="", stdin=""))
        report["validations"][key] = dict(status="passed", commands=proof)
        report["summary"] = CHARTS.bench.summaries(report)
        return report

    def render(self, report):
        path = self.path / "report.json"
        path.write_text(json.dumps(report))
        return CHARTS.render(path, self.path / "charts")

    def test_failed_cells_are_retained_without_zero_scores(self):
        rows = CHARTS.checked_rows(self.report)
        self.assertEqual(len(rows), 44)
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

    def test_v3_names_two_goose_compilers_and_labels(self):
        rows = CHARTS.checked_rows(self.report)
        self.assertEqual({row["compiler"] for row in rows.values()}, {"parent", "candidate"})
        self.assertEqual(CHARTS.compiler_specs(self.report), (
            ("parent", "Experiment Parent", "#d39b28"), ("candidate", "Experiment Candidate", "#087f8c")))
        for field in ("compiler_order", "compiler_labels"):
            report = copy.deepcopy(self.report)
            if field == "compiler_order":
                report[field] = ["candidate", "parent"]
            else:
                report[field].pop("candidate")
            with self.assertRaises(ValueError, msg=field):
                CHARTS.checked_rows(report)
        report = copy.deepcopy(self.report)
        report["compiler_labels"]["candidate"] = ""
        with self.assertRaises(ValueError, msg="empty compiler label"):
            CHARTS.checked_rows(report)
        with self.assertRaises(ValueError, msg="v3 has no retired C++ compiler"):
            CHARTS.checked_rows(self.build_report(CHARTS.V3, V2_LABELS))

    def test_v2_report_with_previous_cpp_remains_readable(self):
        report = self.build_report(CHARTS.V2, V2_LABELS)
        rows = CHARTS.checked_rows(report)
        self.assertEqual(len(rows), 66)
        self.assertEqual({row["compiler"] for row in rows.values()}, {"cpp", "parent", "candidate"})
        self.assertEqual(CHARTS.compiler_specs(report), (("cpp", "Previous C++", "#94a3b8"),
            ("parent", "Goose 58", "#d39b28"), ("candidate", "Goose 59", "#087f8c")))
        native = next(row for row in report["builds"] if (row["compiler"], row["target"]) == ("cpp", "native-c"))
        native["command"].remove("--standalone")
        with self.assertRaises(ValueError, msg="C++ native builds declared --standalone"):
            CHARTS.checked_rows(report)
        report = self.build_report(CHARTS.V2, GOOSE_LABELS)
        with self.assertRaises(ValueError, msg="v2 order includes the C++ compiler"):
            CHARTS.checked_rows(report)

    def test_v1_snapshot_named_report_remains_readable(self):
        report = self.build_report(CHARTS.V1, V2_LABELS)
        report.pop("compiler_order")
        report.pop("compiler_labels")
        old_names = {"parent": "goose56", "candidate": "goose57"}
        report["compilers"] = {old_names.get(name, name): value for name, value in report["compilers"].items()}
        for row in report["builds"]:
            row["compiler"] = old_names.get(row["compiler"], row["compiler"])
        report["summary"] = CHARTS.bench.summaries(report)
        rows = CHARTS.checked_rows(report)
        self.assertTrue(all(name in {"cpp", "goose56", "goose57"} for _, _, name in rows))
        self.assertEqual([label for _, label, _ in CHARTS.compiler_specs(report)],
                         ["Previous C++", "Goose 56", "Goose 57"])
        self.assertEqual(len(rows), 66)

    def test_absent_previous_cpp_binary_keeps_its_recorded_identity(self):
        self.assertEqual(self.render(self.report)["unverified_compilers"], [])
        report = self.build_report(CHARTS.V2, V2_LABELS)
        cpp = Path(report["compilers"]["cpp"]["path"])
        cpp.write_text("rebuilt C++ compiler")
        with self.assertRaises(ValueError, msg="a present binary must still match"):
            CHARTS.checked_rows(report)
        cpp.unlink()
        self.assertEqual(len(CHARTS.checked_rows(report)), 66)
        receipt = self.render(report)
        self.assertEqual(receipt["unverified_compilers"], ["cpp"])
        self.assertTrue((self.path / "charts/compiler-comparison.svg").is_file())
        Path(report["compilers"]["parent"]["path"]).unlink()
        with self.assertRaises(ValueError, msg="only the C++ binary may be absent"):
            CHARTS.checked_rows(report)

    def test_plot_receipt_uses_null_for_unavailable_cells(self):
        rows = CHARTS.checked_rows(self.report)
        fig, ax = CHARTS.plt.subplots()
        self.addCleanup(CHARTS.plt.close, fig)
        values = CHARTS.panel(ax, list(CHARTS.LABELS), "wasm-direct", rows)
        self.assertEqual(len(ax.patches), 1)
        self.assertEqual(sum(value["median_ms"] is None for value in values), 21)
        self.assertEqual(len([label for label in ax.texts if label.get_text() == "unavailable"]), 21)


if __name__ == "__main__":
    unittest.main()
