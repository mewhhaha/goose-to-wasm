#!/usr/bin/env python3
"""Native conformance helpers can link and pin case-declared C sources."""
import contextlib
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("conformance_runner", ROOT / "tests/conformance.py")
CONFORMANCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFORMANCE)


class NativeConformanceSources(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.relative_work = self.work.relative_to(ROOT).as_posix()

    def test_case_native_sources_are_linked_cached_and_pinned(self):
        source = self.work / "same.goose"
        source.write_text("fn main() {}\n")
        helpers = []
        cases = []
        for value in (7, 11):
            helper = self.work / f"helper-{value}.c"
            helper.write_text(f"int helper(void) {{ return {value}; }}\n")
            helpers.append(helper)
            cases.append(dict(
                id=f"native-sources/{value}",
                source=f"{self.relative_work}/same.goose",
                phase="run",
                target="native",
                levels=[0],
                stdin="",
                expect=dict(stdout=f"{value}\n", exit=0),
                debug=False,
                native_sources=[f"{self.relative_work}/{helper.name}"]))

        compiler = self.work / "fake-compiler"
        compiler.write_text("""#!/usr/bin/env python3
from pathlib import Path
import sys

arguments = sys.argv[1:]
output = Path(arguments[arguments.index('-o') + 1])
output.write_text('#include <stdio.h>\\nextern int helper(void);\\nint main(void) { printf(\"%d\\\\n\", helper()); return 0; }\\n')
""")
        compiler.chmod(0o755)

        original = json.loads((ROOT / "tests/conformance/cases.json").read_text())
        manifest = self.work / "cases.json"
        manifest.write_text(json.dumps(dict(upstream=original["upstream"], cases=cases)))
        library = self.work / "stdlib"
        library.mkdir()
        output = self.work / "report"
        arguments = ["conformance.py", "--compiler", str(compiler), "--output-dir", str(output),
                     "--manifest", str(manifest), "--stdlib", str(library), "--levels", "0"]

        with mock.patch.object(sys, "argv", arguments), contextlib.redirect_stdout(None):
            self.assertEqual(CONFORMANCE.main(), 0)

        report = json.loads((output / "report.json").read_text())
        self.assertEqual([row["status"] for row in report["results"]], ["pass", "pass"])
        self.assertEqual([row["stdout_equal"] for row in report["results"]], [True, True])
        self.assertNotEqual(report["results"][0]["compile_command"], report["results"][1]["compile_command"])
        self.assertNotEqual(report["results"][0]["native_command"], report["results"][1]["native_command"])

        helper_paths = [str(path) for path in helpers]
        for path, helper in zip(helper_paths, helpers):
            expected = hashlib.sha256(helper.read_bytes()).hexdigest()
            self.assertEqual(report["input_sha256"][path], expected)
            self.assertEqual(report["input_sha256_after"][path], expected)
        self.assertEqual(report["input_sha256"], report["input_sha256_after"])

        native_commands = [row["command"] for row in report["commands"]
                           if row["command"][0] == shutil.which("gcc")]
        self.assertEqual(len(native_commands), 2)
        # Rows run concurrently, so commands are recorded in completion order.
        self.assertEqual(sorted(next(part for part in command if part in helper_paths) for command in native_commands),
                         sorted(helper_paths))
        for command in native_commands:
            self.assertIn("-rdynamic", command)

    def test_native_link_command_adds_exports_only_with_case_sources(self):
        artifact = Path("program.c")
        expected = ["gcc", "-std=gnu11", "-O0", artifact, "-lm", "-ldl", "-pthread",
                    "-o", artifact.parent / "program"]
        self.assertEqual(CONFORMANCE.native_compile_command("gcc", "-O0", [], artifact, ()), expected)
        linked = CONFORMANCE.native_compile_command("gcc", "-O0", [], artifact, [Path("helper.c")])
        self.assertEqual(linked, ["gcc", "-std=gnu11", "-O0", artifact, Path("helper.c"),
                                  "-rdynamic", "-lm", "-ldl", "-pthread", "-o",
                                  artifact.parent / "program"])
        with self.assertRaisesRegex(ValueError, "ROOT-relative"):
            CONFORMANCE.native_source_paths({"native_sources": ["../outside.c"]})

    def test_native_units_compile_beside_the_runtime_unit(self):
        artifact = Path("program.c")
        units = CONFORMANCE.native_compile_command("gcc", "-O2", ["-DX=1"], artifact, (), 3, Path("runtime.o"))
        self.assertEqual(units, ["sh", "-c", CONFORMANCE.UNITS_SCRIPT, "sh", "gcc", "-O2", "3", artifact,
                                 artifact.parent / "program", Path("runtime.o"), "-DX=1"])
        # Cases with their own C sources still compile as one unit.
        whole = CONFORMANCE.native_compile_command("gcc", "-O2", [], artifact, [Path("helper.c")], 3)
        self.assertEqual(whole[:4], ["gcc", "-std=gnu11", "-O2", artifact])

    def test_native_cache_reuses_successful_builds_across_runs(self):
        source = self.work / "same.goose"
        source.write_text("fn main() {}\n")
        cases = [dict(id=f"native-cache/{value}", source=f"{self.relative_work}/same.goose", phase="run",
                      target="native", levels=[0, 2], stdin="", expect=dict(stdout=f"{value}\n", exit=0),
                      debug=False, native_defines=[f"VALUE={value}"]) for value in (3, 5)]
        compiler = self.work / "fake-compiler"
        compiler.write_text("""#!/usr/bin/env python3
from pathlib import Path
import sys

arguments = sys.argv[1:]
output = Path(arguments[arguments.index('-o') + 1])
output.write_text('#include <stdio.h>\\nint main(void) { printf(\"%d\\\\n\", VALUE); return 0; }\\n')
""")
        compiler.chmod(0o755)
        original = json.loads((ROOT / "tests/conformance/cases.json").read_text())
        manifest = self.work / "cases.json"
        manifest.write_text(json.dumps(dict(upstream=original["upstream"], cases=cases)))
        library = self.work / "stdlib"
        library.mkdir()
        cache = self.work / "native-cache"
        reports = []
        for run in ("cold", "warm"):
            output = self.work / run
            arguments = ["conformance.py", "--compiler", str(compiler), "--output-dir", str(output),
                         "--manifest", str(manifest), "--stdlib", str(library), "--jobs", "4",
                         "--native-cache", str(cache), "--prune-native-cache"]
            with mock.patch.object(sys, "argv", arguments), contextlib.redirect_stdout(None):
                self.assertEqual(CONFORMANCE.main(), 0)
            reports.append(json.loads((output / "report.json").read_text()))
        cold, warm = reports
        self.assertEqual([row["status"] for row in warm["results"]], ["pass"] * 4)
        self.assertEqual(cold["native_cache_summary"], {"builds": 4, "hits": 0})
        self.assertEqual(warm["native_cache_summary"], {"builds": 4, "hits": 4})
        # One binary and one metadata file per distinct define and level; nothing else survives pruning.
        self.assertEqual(len(list(cache.iterdir())), 8)

    def test_native_units_compile_each_runtime_once(self):
        # Emitted C in miniature: the runtime body before the program-units
        # mark, then program functions that unit 0 holds.
        sources = []
        for value in (3, 5):
            source = self.work / f"program-{value}.goose"
            source.write_text(f"// {value}\n")
            sources.append(source)
        compiler = self.work / "fake-compiler"
        compiler.write_text("""#!/usr/bin/env python3
from pathlib import Path
import sys

arguments = sys.argv[1:]
value = Path(arguments[0]).read_text().split()[1]
output = Path(arguments[arguments.index('-o') + 1])
output.write_text('#ifndef G_UNITS\\nint runtime_value(void) { return 40; }\\n#endif\\n'
                  '#ifdef G_RUNTIME_UNIT\\n#else /* program units */\\n#include <stdio.h>\\n'
                  'int runtime_value(void);\\n#if !defined(G_UNIT) || G_UNIT == 0\\n'
                  'int main(void) { printf("%d\\\\n", runtime_value() + ' + value + '); return 0; }\\n#endif\\n#endif\\n')
""")
        compiler.chmod(0o755)
        original = json.loads((ROOT / "tests/conformance/cases.json").read_text())
        cases = [dict(id=f"units/{value}", source=f"{self.relative_work}/program-{value}.goose", phase="run",
                      target="native", levels=[0, 2], stdin="", expect=dict(stdout=f"{40 + value}\n", exit=0))
                 for value in (3, 5)]
        cases.append(dict(id="units/wasm", source=f"{self.relative_work}/program-3.goose", phase="check",
                          target="wasm-direct", levels=[0], stdin="", expect=dict(exit=0)))
        manifest = self.work / "cases.json"
        manifest.write_text(json.dumps(dict(upstream=original["upstream"], cases=cases)))
        library = self.work / "stdlib"
        library.mkdir()
        cache = self.work / "native-cache"
        reports = []
        for run in ("cold", "warm"):
            output = self.work / run
            arguments = ["conformance.py", "--compiler", str(compiler), "--output-dir", str(output),
                         "--manifest", str(manifest), "--stdlib", str(library), "--jobs", "4",
                         "--native-units", "2", "--targets", "native", "--native-cache", str(cache)]
            with mock.patch.object(sys, "argv", arguments), contextlib.redirect_stdout(None):
                self.assertEqual(CONFORMANCE.main(), 0)
            reports.append(json.loads((output / "report.json").read_text()))
        cold, warm = reports
        # --targets keeps the native rows only.
        self.assertEqual([(row["case"], row["level"], row["status"]) for row in cold["results"]],
                         [("units/3", 0, "pass"), ("units/3", 2, "pass"), ("units/5", 0, "pass"), ("units/5", 2, "pass")])
        runtime = [row for row in cold["commands"] if "-DG_RUNTIME_UNIT" in row["command"]]
        # One runtime object per flag, shared by both programs.
        self.assertEqual(sorted(row["command"][2] for row in runtime), ["-O0", "-O2"])
        self.assertEqual(warm["native_cache_summary"], {"builds": 6, "hits": 6})
        self.assertFalse([row for row in warm["commands"] if "-DG_RUNTIME_UNIT" in row["command"]])

    def test_native_cache_rebuilds_case_sources_after_transitive_header_change(self):
        source = self.work / "same.goose"
        source.write_text("fn main() {}\n")
        helper = self.work / "helper.c"
        helper.write_text('#include "value.h"\nint helper(void) { return VALUE; }\n')
        (self.work / "value.h").write_text('#include "detail.h"\n')
        header = self.work / "detail.h"
        compiler = self.work / "fake-compiler"
        compiler.write_text("""#!/usr/bin/env python3
from pathlib import Path
import sys

arguments = sys.argv[1:]
output = Path(arguments[arguments.index('-o') + 1])
output.write_text('#include <stdio.h>\\nextern int helper(void);\\nint main(void) { printf("%d\\\\n", helper()); return 0; }\\n')
""")
        compiler.chmod(0o755)
        original = json.loads((ROOT / "tests/conformance/cases.json").read_text())
        case = dict(id="native-cache/headers", source=f"{self.relative_work}/same.goose", phase="run",
                    target="native", levels=[0, 2], stdin="", expect=dict(stdout="3\n", exit=0),
                    native_sources=[f"{self.relative_work}/helper.c"])
        manifest = self.work / "cases.json"
        manifest.write_text(json.dumps(dict(upstream=original["upstream"], cases=[case])))
        library = self.work / "stdlib"
        library.mkdir()
        cache = self.work / "native-cache"
        reports = []
        for name, value, cached in (("cold", 3, True), ("warm", 3, True),
                                    ("changed", 5, True), ("uncached", 5, False)):
            header.write_text(f"#define VALUE {value}\n")
            output = self.work / name
            arguments = ["conformance.py", "--compiler", str(compiler), "--output-dir", str(output),
                         "--manifest", str(manifest), "--stdlib", str(library), "--jobs", "2"]
            if cached:
                arguments += ["--native-cache", str(cache), "--prune-native-cache"]
            with mock.patch.object(sys, "argv", arguments), contextlib.redirect_stdout(None):
                self.assertEqual(CONFORMANCE.main(), int(value != 3), name)
            report = json.loads((output / "report.json").read_text())
            reports.append(report)
            executions = [report["commands"][row["run_command"]] for row in report["results"]]
            self.assertEqual([row["stdout"] for row in executions], [f"{value}\n"] * 2)
        for report in reports[:3]:
            self.assertEqual(report["native_cache_summary"], {"builds": 2, "hits": 0})
        self.assertEqual([row["status"] for row in reports[2]["results"]], ["fail", "fail"])
        for cached_row, uncached_row in zip(reports[2]["results"], reports[3]["results"]):
            for key in ("status", "phase", "stdout_equal", "exit_equal", "diagnostic_equal"):
                self.assertEqual(cached_row[key], uncached_row[key])
        self.assertEqual(list(cache.iterdir()), [])


class KnownGaps(unittest.TestCase):
    def check(self, statuses, gaps):
        report = {"results": [{"case": case, "level": level, "status": status}
                              for (case, level), status in statuses.items()]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "known-gaps.json"
            path.write_text(json.dumps({"gaps": [list(gap) for gap in gaps]}))
            with contextlib.redirect_stdout(None):
                return CONFORMANCE.known_gaps(report, path)

    def test_recorded_failures_pass(self):
        self.assertEqual(self.check({("a", 0): "pass", ("b", 2): "fail"}, [("b", 2)]), 0)

    def test_unrecorded_failure_fails(self):
        self.assertEqual(self.check({("a", 0): "fail", ("b", 2): "fail"}, [("b", 2)]), 1)

    def test_recorded_gap_that_passes_fails(self):
        self.assertEqual(self.check({("a", 0): "pass", ("b", 2): "pass"}, [("b", 2)]), 1)

    def test_unselected_gaps_are_ignored(self):
        self.assertEqual(self.check({("a", 0): "pass"}, [("b", 2), ("a", 2)]), 0)

    def test_checked_in_record_has_the_open_gaps(self):
        record = json.loads((ROOT / "tests/conformance/known-gaps.json").read_text())
        gaps = {tuple(gap) for gap in record["gaps"]}
        self.assertEqual(len(gaps), len(record["gaps"]))
        cases = {case["id"]: case for case in json.loads((ROOT / "tests/conformance/cases.json").read_text())["cases"]}
        for case, level in gaps:
            self.assertIn(case, cases)
            self.assertIn(level, cases[case]["levels"])


if __name__ == "__main__":
    unittest.main()
