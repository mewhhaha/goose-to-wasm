"""Replay the instrumented and control compilers against one frozen workload.

Stage requires compiler/ at ba9dece with instrument.py applied and workload/ at f89ecf3.
Build probe.wasm with the qualified 065aff3 emitter then use wasm, native, or baseline mode.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("engine",choices=["wasm","native","baseline"])
parser.add_argument("--stage",type=Path,required=True)
parser.add_argument("--repo",type=Path,required=True)
parser.add_argument("--cpu",type=int,default=4)
args=parser.parse_args()
d=args.stage.resolve()
repo=args.repo.resolve()
os.sched_setaffinity(0,{args.cpu})
if args.engine=="wasm":
    runner=[repo/".venv/bin/python",repo/"scripts/run_wasmtime.py",d/"probe.wasm","--cache",d/"probe.cwasm","--"]
elif args.engine=="native": runner=[d/"probe-native"]
else: runner=[repo/"build/lifetime-exit-index-2026-11-18/native-candidate"]
common=["selfhost/main.goose","--stdlib","stdlib"]
def digest(path):
    return hashlib.file_digest(path.open("rb"),"sha256").hexdigest()
for label, argv, expected_code in [
    ("check",common+["--check"],0),
    ("emit",common+["--target","wasm-direct","-O2","--wasm-memory64","--wasm-max-pages","262144","-o",str(d/(args.engine+".wasm.out"))],0),
    ("negative",[str(repo/"tests/fixtures/contracts/upstream-differential/harvest/private_snapshot_parameters/98f0101e11.goose"),"--stdlib","stdlib","--check"],1),
]:
    result=subprocess.run(runner+argv,cwd=d/"workload",capture_output=True,timeout=600)
    (d/f"{args.engine}-{label}.out").write_bytes(result.stdout)
    err=result.stderr
    if args.engine=="wasm" and err.endswith(b'\n\n'):
        # CLI print adds a trailing terminator to the guest's already newline-terminated stderr.
        err=err[:-1]
    (d/f"{args.engine}-{label}.err").write_bytes(err)
    assert result.returncode==expected_code,(args.engine,label,result)
    report=dict(cpu=args.cpu,engine=args.engine,arguments=argv,exit=result.returncode,
                stdout_sha256=hashlib.sha256(result.stdout).hexdigest(),
                stderr_sha256=hashlib.sha256(err).hexdigest())
    if label=="emit":
        report["artifact_sha256"]=digest(d/(args.engine+".wasm.out"))
        assert report["artifact_sha256"]=="31783c320929638535d7c50da591954cdf1eebf3af83f2d1f5c3ab5a7089e468",report
    (d/f"{args.engine}-{label}.json").write_text(json.dumps(report,indent=2)+"\n")
    print(args.engine,label,result.returncode,flush=True)
