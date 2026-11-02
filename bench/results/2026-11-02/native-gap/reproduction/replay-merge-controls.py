import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))
from bench.qualify_compiler import BACKENDS, LEVELS, combine, digest, expected_configuration
from run_differential import cases

OUTPUT = ROOT / "build/native-gap/qualification-smoke"
FILTER = "checked-leaves/scalars"
selected = [case for case in cases() if FILTER in case.name]
base = {}
configurations = {}
for backend in BACKENDS:
    for level in LEVELS:
        key = (backend, level)
        path = OUTPUT / "shards" / f"{backend}-O{level}" / "report.json"
        report = json.loads(path.read_text())
        report["_report_sha256"] = digest(path)
        report["_command"] = ["replay", backend, str(level)]
        base[key] = report
        configurations[key] = expected_configuration(backend, level, FILTER)
compiler_hash = base[("native", 0)]["compiler_sha256"]
smoke = json.loads((OUTPUT / "report.json").read_text())

controls = {}
cases_to_check = {}
missing = copy.deepcopy(base)
missing.pop(("direct", 2))
cases_to_check["missing_shard"] = missing

duplicate = copy.deepcopy(base)
duplicate[("native", 0)]["results"].append(copy.deepcopy(duplicate[("native", 0)]["results"][0]))
duplicate[("native", 0)]["observations"] += 1
cases_to_check["duplicate_runtime_row"] = duplicate

wrong_stdout = copy.deepcopy(base)
wrong_stdout[("direct", 0)]["results"][0]["stdout"] = "wrong stdout"
cases_to_check["wrong_stdout"] = wrong_stdout

wrong_configuration = copy.deepcopy(base)
wrong_configuration[("direct", 2)]["configuration"]["skip_refusals"] = False
cases_to_check["wrong_configuration"] = wrong_configuration

for name, reports in cases_to_check.items():
    try:
        combine(reports, selected, configurations, compiler_hash, True)
    except AssertionError as error:
        controls[name] = {"rejected": True, "reason": str(error)[:240]}
    else:
        controls[name] = {"rejected": False, "reason": "merge unexpectedly accepted invalid reports"}

result = {"smoke_report": str(OUTPUT / "report.json"), "compiler_sha256": compiler_hash,
          "observations": smoke["observations"], "cases": smoke["cases"], "failures": smoke["failures"],
          "native_stdout_comparisons": smoke["qualification_execution"]["native_stdout_comparisons"],
          "negative_controls": controls}
result_path = ROOT / "build/native-gap/merge-controls.json"
result_path.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
if not all(item["rejected"] for item in controls.values()):
    raise SystemExit(1)
