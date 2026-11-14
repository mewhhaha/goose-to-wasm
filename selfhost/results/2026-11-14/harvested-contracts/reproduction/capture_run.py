import sys, os, subprocess, hashlib, shutil, unittest, pathlib
T="/tmp/claude-1000/-home-jacobt-src-goose-to-wasm/b5a2993b-17a9-4b5d-96f3-a852f1f5fdeb/scratchpad/test-port/tests"
CAP="/tmp/claude-1000/-home-jacobt-src-goose-to-wasm/b5a2993b-17a9-4b5d-96f3-a852f1f5fdeb/scratchpad/diff-upstream/cap"
sys.path.insert(0,T); os.chdir(T)
mod=sys.argv[1]
d=pathlib.Path(CAP)/mod; d.mkdir(exist_ok=True)
G=os.environ["GOOSE_COMPILER"]
orig=subprocess.run
def wrap(cmd,*a,**k):
    try:
        if isinstance(cmd,(list,tuple)) and str(cmd[0])==G:
            for x in cmd[1:]:
                x=str(x)
                if x.endswith(".goose") and os.path.exists(x):
                    txt=open(x).read(); h=hashlib.sha1(txt.encode()).hexdigest()[:10]
                    tgt=cmd[cmd.index("--target")+1] if "--target" in cmd else "?"
                    (d/f"{h}.goose").write_text(txt)
                    with open(d/"cmds.txt","a") as f: f.write(f"{h} target={tgt} {' '.join(str(c) for c in cmd[2:] if str(c) not in (x,))}\n")
    except Exception as e: print("cap err",e,file=sys.stderr)
    return orig(cmd,*a,**k)
subprocess.run=wrap
for n in dir(unittest.TestCase):
    if n.startswith("assert") and not n.startswith("_"): setattr(unittest.TestCase,n,lambda *a,**k:None)
unittest.main(module=None,argv=["x",mod],exit=False)
