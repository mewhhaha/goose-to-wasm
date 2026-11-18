"""Test compiler layouts on held-out sources, checked against the same native compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("repo", type=Path)
parser.add_argument("compiler_stage", type=Path)
parser.add_argument("project_stage", type=Path)
parser.add_argument("controls", type=Path, help="frozen project-calibrated controls from compiler-record-access/tools/modules.sh")
parser.add_argument("out", type=Path)
parser.add_argument("--cpu", type=int, default=3)
parser.add_argument("--rounds", type=int, default=3)
parser.add_argument("--prior", type=Path, help="reuse recorded reference and correctness rows for the identical modules")
parser.add_argument("--report", default="validation.json")
parser.add_argument("--extra-case", action="append", default=[])
a = parser.parse_args()
repo, compiler, project, controls, out = [p.resolve() for p in (a.repo, a.compiler_stage, a.project_stage, a.controls, a.out)]
sys.path.insert(0, str(repo / "bench"))
from selfhost_comparison import identity, verify_frozen_source
os.sched_setaffinity(0, {a.cpu})
_, hard = resource.getrlimit(resource.RLIMIT_STACK)
resource.setrlimit(resource.RLIMIT_STACK,(256 << 20, hard))
for stage in [compiler, project]:
    manifest = json.loads((stage / "builds.json").read_text())
    verify_frozen_source(stage / "source", manifest["source_commit"], manifest["source_archive_sha256"])
rust = repo / "host/rust/target/release/goose-wasmtime"
native = compiler / "build-1/compiler-native"
flags = ["--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144"]
work = out / "heldout"
work.mkdir(exist_ok=True)
blot = json.loads((repo / "bench/fixtures/compiler-goose/manifest.json").read_text())
archive = repo / blot["archive"]["path"]
assert identity(archive)["sha256"] == blot["archive"]["sha256"]
with tarfile.open(archive) as tf:
    tf.extractall(work / "blot", filter="data")
example_names = ["vm","sudoku","functions","errors","sieve","life","maze"]
for name in example_names:
    path = Path("examples") / (name + ".goose")
    dst = work / path
    dst.parent.mkdir(exist_ok=True)
    dst.write_bytes(subprocess.check_output(["git", "show", "4e9b78e:" + str(path)], cwd=repo))
# 8192 leaf functions plus their 8191 callers, reached through a balanced tree.
generated = work / "tree.goose"
with generated.open("w") as source:
    for i in reversed(range(1, 1 << 14)):
        rhs = f"x + {i}"
        if i < 1 << 13:
            rhs = f"tree_{i*2}(x) + tree_{i*2+1}(x)"
        print(f"fn tree_{i}(x: i64) -> i64 {{ return {rhs}; }}", file=source)
    print("fn main() { print(tree_1(1)); }",file=source)
# This additional project stresses reference-return summaries at every internal node.
# It was added after the raw training policy failed on the frozen compiler.
borrows = work / "borrow-tree.goose"
with borrows.open("w") as source:
    print("struct Pair { left: i64, right: i64 }",file=source)
    for i in reversed(range(1,1 << 13)):
        print(f"fn borrow_{i}(p: Pair&, select: bool) -> i64& {{",file=source)
        if i < 1 << 12:
            print(f"    if select {{ return borrow_{i*2}(p, select); }}",file=source)
            print(f"    return borrow_{i*2+1}(p, select);",file=source)
        elif i % 2:
            print("    return p.left;",file=source)
        else:
            print("    return p.right;",file=source)
        print("}",file=source)
    print("fn main() { var p = Pair { left: 1, right: 2 }; print(borrow_1(p, true)); }",file=source)
modules = {"trained32":out / "trained32.wasm", "uniform32":out / "uniform32.wasm", "calibrated32":controls / "general32.wasm", "general64":controls / "general64.wasm"}
for spec in a.extra_case:
    name, path = spec.split("=",1)
    modules[name] = Path(path).resolve(strict=True)
datasets = {}
for mode in ["check","emit"]:
    datasets["self-" + mode] = (project / "source", ["selfhost/main.goose","--stdlib","stdlib"], mode)
datasets["blot-parse"] = (work / "blot/compiler-goose", ["src/main.goose","--stdlib","../stdlib","--target","native"],"parse")
datasets["tree-emit"] = (work,["tree.goose","--stdlib",str(compiler / "source/stdlib")],"emit")
datasets["borrow-tree-emit"] = (work,["borrow-tree.goose","--stdlib",str(compiler / "source/stdlib")],"emit")
for name in example_names:
    datasets[name + "-emit"] = (work,["examples/" + name + ".goose","--stdlib",str(compiler / "source/stdlib")],"emit")
def invoke(module, dataset):
    cwd, args, mode = datasets[dataset]
    artifact = work / "output.wasm"
    artifact.unlink(missing_ok=True)
    args = list(args)
    if mode == "emit":
        args += [*flags, "-o", artifact]
    else:
        args += ["--" + mode]
    cmd = [native]
    timing = work / "timing.json"
    timing.unlink(missing_ok=True)
    if module != "native":
        cmd = [rust, modules[module], "--cache", work / (module + ".cwasm"), "--timing-json",timing,"--"]
    result = subprocess.run([*cmd,*args],cwd=cwd,capture_output=True,timeout=150)
    r = dict(status=result.returncode)
    if result.stderr:
        r["stderr"] = result.stderr[:400].decode(errors="replace")
    if result.stdout:
        r["stdout_sha256"] = hashlib.sha256(result.stdout).hexdigest()
    if artifact.exists():
        r.update(emission=identity(artifact))
    seconds = None
    if timing.exists():
        seconds = json.loads(timing.read_text())["start_function_ns"] / 1e9
    return r, seconds
report = dict(compiler_commit=json.loads((compiler/"builds.json").read_text())["source_commit"],
              workload=json.loads((project/"builds.json").read_text())["source_commit"],
              compiler_archive_sha256=json.loads((compiler/"builds.json").read_text())["source_archive_sha256"],
              workload_archive_sha256=json.loads((project/"builds.json").read_text())["source_archive_sha256"],
              fixture_sha256=identity(archive)["sha256"], generated=identity(generated), borrow_tree=identity(borrows),
              examples={n:identity(work/"examples"/(n+".goose")) for n in example_names},
              cpu=a.cpu, rust_host=identity(rust), modules={k:identity(p) for k,p in modules.items()},
              native=identity(native), calibrated_profile_sha256=identity(controls/"regions.txt")["sha256"],
              correctness={}, self_timing_s={}, training=json.loads((out/"training.json").read_text()))
prior = {}
if a.prior:
    old = json.loads(a.prior.read_text())
    for key in ["cpu","workload_archive_sha256","compiler_archive_sha256","generated","examples","fixture_sha256","rust_host","native","calibrated_profile_sha256","training"]:
        assert report[key] == old[key], key
    for label, identity_value in old["modules"].items():
        assert report["modules"][label] == identity_value
    prior = old["correctness"]
target = out / a.report
def save():
    target.write_text(json.dumps(report,indent=2)+"\n")
for dataset in datasets:
    if dataset in prior:
        reference = prior[dataset]["reference"]
    else:
        reference, _ = invoke("native",dataset)
    assert reference["status"] == 0 and "stderr" not in reference, (dataset,reference)
    if datasets[dataset][2] == "emit":
        assert "emission" in reference
    runs = dict(prior.get(dataset,{}).get("runs",{}))
    report["correctness"][dataset] = dict(reference=reference, runs=runs)
    for label in modules:
        if label in runs:
            continue
        observed, seconds = invoke(label,dataset)
        row = dict(matches_native=observed == reference)
        if observed != reference:
            row["observed"] = observed
        runs[label] = row
        save()
        print(dataset,label,observed["status"],row["matches_native"],seconds,flush=True)
for mode in ["self-check","self-emit"]:
    eligible = [k for k in modules if report["correctness"][mode]["runs"][k]["matches_native"]]
    times = {k:[] for k in eligible}
    report["self_timing_s"][mode] = times
    for index in range(a.rounds):
        order = list(eligible)
        if index % 2:
            order.reverse()
        for label in order:
            observed, seconds = invoke(label,mode)
            assert observed == report["correctness"][mode]["reference"], (mode,label,observed)
            times[label].append(seconds)
            print(mode,label,index,seconds,flush=True)
            save()
