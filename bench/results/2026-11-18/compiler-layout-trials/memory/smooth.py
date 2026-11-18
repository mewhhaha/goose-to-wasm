"""Dampen the dominance of individual outliers in training with square-root weights.

Run after train.py. Only training high-water marks are inputs to the policy.
This is a follow-up to the raw maxima failing on the frozen compiler.
"""
import argparse
from math import isqrt
import os
from pathlib import Path
import resource
import subprocess

args = argparse.ArgumentParser(description=__doc__)
args.add_argument("compiler_stage", type=Path)
args.add_argument("out", type=Path)
args.add_argument("--cpu", type=int, default=3)
a = args.parse_args()
os.sched_setaffinity(0, {a.cpu})
resource.setrlimit(resource.RLIMIT_STACK, (256 << 20,resource.getrlimit(resource.RLIMIT_STACK)[1]))
stage, out = a.compiler_stage.resolve(), a.out.resolve()
src, dest = out / "training-max.profile", out / "training-root.profile"
with dest.open("w") as file:
    for line in src.read_text().splitlines():
        i, peak = map(int,line.split())
        print(i,isqrt(peak << 16),file=file)
subprocess.run([stage / "build-1/compiler-native", "selfhost/main.goose","--stdlib","stdlib","--target","wasm-direct","-O2",
                "--wasm-max-pages","65535","--wasm-region-profile",dest,"-o",out / "root32.wasm"], cwd=stage/"source",check=True)
