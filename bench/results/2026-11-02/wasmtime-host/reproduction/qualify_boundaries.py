"""Record the public-ABI suite with frozen source and host identities."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/wasmtime-host'
HOST=ROOT/'build/bin/goose-wasmtime'
meta=json.loads(HOST.with_suffix('.json').read_text())
sources=[ROOT/'tests/test_native_wasmtime.py',ROOT/'host/wasmtime.cpp',
         ROOT/'scripts/build_wasmtime_host.py',ROOT/'scripts/run_wasmtime.py',ROOT/'host/wasmtime-sdk.json',Path(__file__).resolve()]
paths=sources+[HOST,HOST.with_suffix('.json'),Path(meta['library']),Path(sys.executable).resolve()]
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={str(p):digest(p)for p in paths}
command=[sys.executable,str(sources[0]),'--host',str(HOST)]
result=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=120)
(OUT/'boundaries.log').write_bytes(result.stdout+result.stderr)
count=re.search(rb'Ran (\d+) tests?',result.stderr)
methods=0
if count:methods=int(count[1])
after={str(p):digest(p)for p in paths}
passed=result.returncode==0 and methods==10 and before==after
status='fail'
if passed:status='pass'
report={'schema':'goose-native-host-boundaries-v1','status':status,'methods':methods,
        'exit_code':result.returncode,'command':command,'source_sha256':{str(p):before[str(p)]for p in sources},
        'input_sha256':before,'input_sha256_after':after,'host_sha256':digest(HOST),
        'library_sha256':digest(Path(meta['library'])),'log':'boundaries.log'}
(OUT/'boundary-report.json').write_text(json.dumps(report,indent=2)+'\n')
if not passed:raise SystemExit('Boundary suite failed; see boundaries.log')
print('PASS',methods,'boundary methods with source/host before-after pins')
