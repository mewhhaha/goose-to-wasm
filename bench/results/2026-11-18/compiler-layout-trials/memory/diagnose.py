"""Print the exact failing reserve and compare each layout with a successful high-water trace.

Uses diagnostic compiler copies. The original compiler builds a separate emitter
that logs the failing reserve operands. The probe patches only the diagnostic
module's region table to match the exact released layout.
"""
import argparse
import json
import os
from pathlib import Path
import resource
import shutil
import struct
import subprocess
import sys

def leb(data, pos):
    value, shift = 0, 0
    while True:
        byte = data[pos]
        pos += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, pos
        shift += 7

def region_table(wasm):
    pos = 8
    while pos < len(wasm):
        typ = wasm[pos]
        size, start = leb(wasm, pos+1)
        pos = start + size
        if typ == 6:
            globals_count, i = leb(wasm,start)
            values = []
            for _ in range(globals_count):
                _, _, opcode = wasm[i:i+3]
                assert opcode in (0x41,0x42)
                value, i = leb(wasm,i+3)
                assert wasm[i] == 11
                i += 1
                values.append(value)
            count, table_address = values[8:10]
        elif typ == 11:
            segments, i = leb(wasm,start)
            for _ in range(segments):
                flag, i = leb(wasm,i)
                assert not flag
                addr, i = leb(wasm,i+1)
                assert wasm[i] == 11
                size, i = leb(wasm,i+1)
                if addr == table_address:
                    width = size // (count+1)
                    assert width in (4, 8) and size == width*(count+1)
                    word = {4:"I",8:"Q"}[width]
                    return width, (i,i+size), list(struct.unpack("<"+word*(count+1),wasm[i:i+size]))
                i += size
    raise ValueError("region table not found")

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ("repo","compiler_stage","project_stage","controls","out"):
        p.add_argument(arg,type=Path)
    p.add_argument("--cpu",type=int,default=3)
    a = p.parse_args()
    os.sched_setaffinity(0,{a.cpu})
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20,resource.getrlimit(resource.RLIMIT_STACK)[1]))
    repo, stage, project, controls, out = [path.resolve() for path in (a.repo,a.compiler_stage,a.project_stage,a.controls,a.out)]
    sys.path.insert(0,str(repo/"bench"))
    from selfhost_comparison import identity
    src, native, sandbox = stage/"source",stage/"build-1/compiler-native",out/"diagnostics"
    sandbox.mkdir(exist_ok=True)
    copy = sandbox/"source"
    shutil.copytree(src,copy,dirs_exist_ok=True)
    path = copy/"selfhost/codegen.goose"
    code = path.read_text()
    old = 'cg_get(f, bytes); cg_get(f, limit); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");'
    new = '''cg_get(f, bytes); cg_get(f, limit); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x56);
    cg_begin(f, 0x04, 0x40);
    cg_get(f, limit); wa_load(f.code, ww(1)); wa_extend(f.code); wb_op(f.code, 0x10, CG_PRINT_U64); wb_op(f.code, 0x10, CG_NEWLINE);
    cg_get(f, limit); wa_extend(f.code); wb_op(f.code, 0x10, CG_PRINT_U64); wb_op(f.code, 0x10, CG_NEWLINE);
    cg_get(f, cursor); wa_extend(f.code); wb_op(f.code, 0x10, CG_PRINT_U64); wb_op(f.code, 0x10, CG_NEWLINE);
    cg_get(f, bytes); wb_op(f.code, 0x10, CG_PRINT_U64); wb_op(f.code, 0x10, CG_NEWLINE);
    cg_abort(p, m, f, node, "data region exhausted"); cg_end(f);'''
    assert code.count(old) == 1
    path.write_text(code.replace(old,new))
    host = repo/"host/rust/target/release/goose-wasmtime"
    opts = ["selfhost/main.goose","--stdlib","stdlib","--target","wasm-direct","-O2"]
    wide = ["--wasm-memory64","--wasm-max-pages","262144"]
    emitter = sandbox/"emitter.wasm"
    subprocess.run([native,*opts,*wide,"-o",emitter],cwd=copy,check=True)
    def build_diag(name,flags):
        diag = sandbox/(name+".wasm")
        subprocess.run([host,emitter,"--cache",sandbox/"emitter.cwasm","--",*opts,*flags,"-o",diag],cwd=src,check=True)
        return diag
    diags = {4:build_diag("narrow",["--wasm-max-pages","65535"]),8:build_diag("wide",wide)}
    controls_by_label = {"uniform32":out/"uniform32.wasm","trained32":out/"trained32.wasm","root32":out/"root32.wasm",
                         "calibrated32":controls/"general32.wasm","general64":controls/"general64.wasm"}
    tasks = {"self-check":(project/"source",["selfhost/main.goose","--stdlib","stdlib","--check"]),
             "blot-parse":(out/"heldout/blot/compiler-goose",["src/main.goose","--stdlib","../stdlib","--target","native","--parse"]),
             "tree-emit":(out/"heldout",["tree.goose","--stdlib",str(src/"stdlib"),*opts[3:],*wide,"-o",sandbox/"tree.wasm"])}
    truth=json.loads((out/"validation-root.json").read_text())["correctness"]
    reports = {}
    for name,original in controls_by_label.items():
        data = original.read_bytes()
        width, (start,end), bounds = region_table(data)
        candidate = bytearray(diags[width].read_bytes())
        _, (a,b), old_bounds = region_table(candidate)
        assert len(bounds)==len(old_bounds) and old_bounds[0]==bounds[0] and old_bounds[-1]==bounds[-1]
        candidate[a:b] = data[start:end]
        diag = sandbox/(name+"-trace.wasm")
        diag.write_bytes(candidate)
        results={}
        for dataset,(cwd,arguments) in tasks.items():
            known=truth[dataset]["runs"][name]
            if known["matches_native"]:
                continue
            r=subprocess.run([host,diag,"--cache",sandbox/(name+".cwasm"),"--",*arguments],cwd=cwd,capture_output=True)
            stderr=r.stderr.decode()
            assert r.returncode == known["observed"]["status"] and stderr == known["observed"]["stderr"], (dataset,name,r)
            raw=r.stdout.decode().split()
            row = {"error":stderr.strip()}
            if raw:
                base,limit,cursor,request=map(int,raw)
                index=bounds.index(base)
                assert bounds[index+1]-3*width == limit and cursor+request>limit
                row.update(region=index,usable_bytes=limit-base,cursor_bytes=cursor-base,
                           requested_bytes=request,needed_bytes_at_trap=cursor+request-base)
            results[dataset]=row
            print(name,dataset,row,flush=True)
        reports[name]=dict(module=identity(original),diagnostic=identity(diag),failed=results)
    # This is a separate generous-address-space reference for the 450-module parse.
    flags=["--wasm-memory64","--wasm-max-pages","4194304","--wasm-region-stats"]
    generous=sandbox/"generous64.wasm"
    subprocess.run([native,*opts,*flags,"-o",generous],cwd=src,check=True)
    cwd,arguments=tasks["blot-parse"]
    profile = sandbox/"blot.profile"
    env={**os.environ,"GOOSE_REGION_PROFILE":str(profile)}
    r=subprocess.run([host,generous,"--cache",sandbox/"generous.cwasm","--",*arguments],cwd=cwd,capture_output=True,env=env)
    peaks={int(i):int(n) for i,n in (line.split() for line in profile.read_text().splitlines())}
    wide_result=dict(module=identity(generous),status=r.returncode,stderr=r.stderr.decode(),profile=identity(profile),
                    stdout=r.stdout.decode(),top_peaks=sorted(peaks.items(),key=lambda x:-x[1])[:10])
    if r.returncode == 0:
        blot_oracle=sandbox/"blot-oracle32.wasm"
        subprocess.run([native,*opts,"--wasm-max-pages","65535","--wasm-region-profile",profile,
                        "-o",blot_oracle],cwd=src,check=True)
        r=subprocess.run([host,blot_oracle,"--cache",sandbox/"blot-oracle32.cwasm","--",*arguments],cwd=cwd,capture_output=True)
        wide_result["blot_trained_32"]=dict(module=identity(blot_oracle),status=r.returncode,
                                             stderr=r.stderr.decode(),stdout=r.stdout.decode())
    # A fitting project-calibrated 32-bit module measures actual narrow required peaks.
    calibrated=sandbox/"calibrated32-stats.wasm"
    subprocess.run([native,*opts,"--wasm-max-pages","65535","--wasm-region-profile",controls/"regions.txt","--wasm-region-stats","-o",calibrated],cwd=src,check=True)
    profile=sandbox/"self-narrow.profile"
    env["GOOSE_REGION_PROFILE"]=str(profile)
    cwd,arguments=tasks["self-check"]
    subprocess.run([host,calibrated,"--cache",sandbox/"self.cwasm","--",*arguments],cwd=cwd,env=env,check=True)
    peaks={int(i):int(n) for i,n in (line.split() for line in profile.read_text().splitlines())}
    undersized={}
    for name,original in controls_by_label.items():
        width,_,bounds=region_table(original.read_bytes())
        if width!=4:
            continue
        undersized[name]=[dict(region=i,usable_bytes=bounds[i+1]-bounds[i]-3*width,peak_bytes=n)
                          for i,n in peaks.items() if n > bounds[i+1]-bounds[i]-3*width]
    report=dict(reserve_failures=reports,blot_256gib=wide_result,self_check_peaks=dict(module=identity(calibrated),
                 profile=identity(profile),undersized=undersized))
    (out/"diagnosis.json").write_text(json.dumps(report,indent=2)+"\n")
    print("generous",wide_result,flush=True)
if __name__=="__main__":
    main()
