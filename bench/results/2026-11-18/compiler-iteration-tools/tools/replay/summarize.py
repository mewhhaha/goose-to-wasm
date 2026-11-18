"""Validate entry partitions then assemble the operation counts and tool identities."""
from importlib.metadata import version
import hashlib
import json
from pathlib import Path
import subprocess
import sys

d=Path(sys.argv[1]).resolve()
root=Path(sys.argv[2]).resolve()
fields="visited summary_stamp leaf_stamp filtered applied productive visits_adding visits_updating effects_added effects_updated revision_only mapping_context mapped".split()
calls="calls chain_hits compact_reads_bypassed noncompact_bypasses max_replay_depth".split()
def sha(path):
    with path.open("rb") as fp: return hashlib.file_digest(fp,"sha256").hexdigest()
def fingerprint(rev):
    return subprocess.check_output(['git','rev-parse',rev],cwd=root,text=True).strip()
def parse(path):
    rows={}; phases={}
    raw=path.read_text().splitlines()
    for line in raw:
        tag,phase,*v=line.split()
        phase=["discovery","validation"][int(phase)]
        if tag=="REPLAY_CALLS":
            assert phase not in phases
            phases[phase]=dict(zip(calls,map(int,v),strict=True))
        else:
            assert tag=="REPLAY_ROW"
            k,*nums=v
            row=dict(zip(fields,map(int,nums),strict=True)); rows.setdefault(phase,{})[int(k)]=row
            assert row["visited"]==sum(row[f] for f in ["summary_stamp","leaf_stamp","filtered","applied"])
            assert max(row["visits_adding"],row["visits_updating"])<=row["productive"]<=row["visits_adding"]+row["visits_updating"]
    return {phase:dict(**info,by_kind=rows.get(phase,{}),total={f:sum(r[f] for r in rows.get(phase,{}).values()) for f in fields}) for phase,info in phases.items()}
compiler=fingerprint("ba9dece")
workload=fingerprint("f89ecf3")
report={"compiler_commit":compiler,"workload_commit":workload,"emitter_commit":fingerprint("065aff3"),"probe_wasm_width":64,"clang":subprocess.check_output(["clang-23","--version"],text=True).splitlines()[0],"wasmtime":version("wasmtime"),"workloads":{}}
report["sha256"]={str(p):sha(root/p) for p in map(Path,["build/bin/goose","build/lifetime-exit-index-2026-11-18/native-candidate"])}
report["sha256"].update({str(p.name):sha(p) for p in [d/"probe.wasm",d/"probe.c",d/"probe-native",d/"instrument.py",d/"compiler/selfhost/checker_lifetimes.goose",Path("/usr/bin/clang-23")]})
report["wasm_command"]="--target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144"
report["native_build_flags"]="-std=gnu11 -w -O1 -lm -ldl -pthread"
for mode in ["check","emit","negative"]:
    controls={e:json.loads((d/f"{e}-{mode}.json").read_text()) for e in ['native','wasm','baseline']}
    if mode=="negative":
        baseline_diag=(d/"baseline-negative.err").read_bytes()
        assert baseline_diag and all((d/f"{e}-negative.err").read_bytes()==baseline_diag for e in ["native","wasm"])
    else:
        assert all((d/f"{e}-{mode}.err").read_bytes()==b'' for e in controls)
    assert (d/f"baseline-{mode}.out").read_bytes()==b''
    assert (d/f"native-{mode}.out").read_bytes()==(d/f"wasm-{mode}.out").read_bytes(), mode
    counts=parse(d/f"native-{mode}.out")
    assert counts or mode=="negative"
    if mode=="emit": assert len({v["artifact_sha256"] for v in controls.values()})==1
    report["workloads"][mode]={"runs":controls,"counts":counts}
if (d/"runs.out").is_file() and (d/"runs.out").stat().st_size:
    data=(d/"runs.out").read_text().splitlines()
    hist=[x for x in data if x.startswith("READ_STAMP_RUN ")]
    assert [x for x in data if not x.startswith("READ_STAMP_RUN ")]==(d/"wasm-check.out").read_text().splitlines()
    assert len(hist)==14 and not (d/"runs.err").read_bytes()
    report["stamp_runs"]={}
    for phase,label in enumerate(["discovery","validation"]):
        buckets=[]
        for line in hist:
            _,group,bucket,runs,items=line.split()
            if int(group)==phase: buckets.append(dict(minimum=2**int(bucket),runs=int(runs),entries=int(items)))
        assert sum(bucket["entries"] for bucket in buckets)==report["workloads"]["check"]["counts"][label]["by_kind"][3]["leaf_stamp"]
        report["stamp_runs"][label]=buckets
    report["sha256"]["runs.wasm"]=sha(d/"runs.wasm")
    report["sha256"]["stamp_runs.py"]=sha(d/"stamp_runs.py")
(d/"counts.json").write_text(json.dumps(report,indent=2)+"\n")
for mode in ["check","emit"]:
  for phase,row in report['workloads'][mode]['counts'].items():
    print(mode,phase,row['total'])
