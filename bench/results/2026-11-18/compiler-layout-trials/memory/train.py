"""Build compiler layouts with calibration isolated from the held-out workloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("repo", type=Path)
parser.add_argument("compiler_stage", type=Path)
parser.add_argument("out", type=Path)
parser.add_argument("--cpu", type=int, default=3)
a = parser.parse_args()
repo, compiler, out = [p.resolve() for p in (a.repo, a.compiler_stage, a.out)]
out.mkdir(exist_ok=True, parents=True)
os.sched_setaffinity(0, {a.cpu})
_, hard = resource.getrlimit(resource.RLIMIT_STACK)
resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, hard))
native = compiler / "build-1/compiler-native"
rust = repo / "host/rust/target/release/goose-wasmtime"
flags = ["--target", "wasm-direct", "-O2"]
wide = ["--wasm-memory64", "--wasm-max-pages", "262144"]
narrow = ["--wasm-max-pages", "65535"]
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def call(args, cwd=repo, env=None):
    result = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, env=env)
    if result.returncode:
        raise RuntimeError((args, result.returncode, result.stderr))
def build(label, extra):
    path = out / (label + ".wasm")
    call([native, "selfhost/main.goose", "--stdlib", "stdlib", *flags, *extra, "-o", path], compiler / "source")
    return path
stats = build("general64-stats", [*wide, "--wasm-region-stats"])
work = out / "training"
work.mkdir(exist_ok=True)
names = ["squares", "sorting", "tour"]
maximum = {}
training = []
for name in names:
    source = Path("examples") / (name + ".goose")
    # Read committed example bytes, independently of the working tree.
    local = work / source
    local.parent.mkdir(exist_ok=True)
    local.write_bytes(subprocess.check_output(["git", "show", "4e9b78e:" + str(source)], cwd=repo))
    env = os.environ.copy()
    profile = work / (name + ".profile")
    env["GOOSE_REGION_PROFILE"] = str(profile)
    args = [source, "--stdlib", compiler / "source/stdlib", *flags, *wide]
    emitted, reference = work / (name + ".wasm"), work / (name + "-reference.wasm")
    call([rust, stats, "--cache", out / "stats.cwasm", "--", *args, "-o", emitted], work, env)
    call([native, *args, "-o", reference], work)
    assert sha(emitted) == sha(reference)
    observed = {int(i): int(n) for i,n in (line.split() for line in profile.read_text().splitlines())}
    for i, n in observed.items():
        maximum[i] = max(maximum.get(i, 0), n)
    training.append(dict(name=name, source_sha256=sha(local), emitted_sha256=sha(emitted),
                         profile_sha256=sha(profile), used_regions=len(observed), peak_bytes=max(observed.values())))
auto = out / "training-max.profile"
auto.write_text("".join(f"{i} {n}\n" for i,n in sorted(maximum.items())))
uniform = build("uniform32", narrow)
trained = build("trained32", [*narrow, "--wasm-region-profile", auto])
report = dict(training=training, policy="elementwise maximum of 3 training emission peaks, release layout code and floor",
              cpu=a.cpu, compiler_sha256=sha(native), host_sha256=sha(rust), collector_sha256=sha(stats),
              profile_sha256=sha(auto), compiler_module_sha256={"uniform32":sha(uniform), "trained32":sha(trained)})
(out / "training.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2), flush=True)
