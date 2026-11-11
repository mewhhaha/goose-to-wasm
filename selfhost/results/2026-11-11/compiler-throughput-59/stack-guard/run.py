# Adapted from snapshot 58's native-stack-position-58/run-header.py: same 8 profiles and checks,
# parent (snapshot 58 native/) and candidate (working tree native/storage.h). The candidate fixture
# expects the main thread's bound to be read by g_runtime_start (EAGER_MAIN=1).
from pathlib import Path
import subprocess,json,os,time,re,hashlib,sys
r=Path('/var/tmp/goose-perf/stackguard'); cand=Path(sys.argv[1])
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
profiles=[('clang-O0','clang-23',['-O0'],False),('clang-O2','clang-23',['-O2'],False),('gcc-O0','gcc',['-O0'],False),('gcc-O2','gcc',['-O2'],False),('clang-SAN','clang-23',['-O1','-g','-fsanitize=address,undefined,pointer-overflow','-fno-sanitize-recover=all'],False),('gcc-SAN','gcc',['-O1','-g','-fsanitize=address,undefined,pointer-overflow','-fno-sanitize-recover=all'],False),('clang-Tiny','clang-23',['-O2','-D__TINYC__=1'],True),('gcc-Tiny','gcc',['-O2','-D__TINYC__=1'],True)]
report={'status':'running','fixture_sha256':sha(r/'whole-header.c'),'parent_storage_sha256':sha(r/'parent/native/storage.h'),'candidate_storage_sha256':sha(cand/'storage.h'),'rows':[]}
for label,base,eager in [('parent',r/'parent/native',0),('candidate',cand,1)]:
 for name,cc,flags,fallback in profiles:
  fast=int(not fallback);prefix=label+'-'+name;binary=r/prefix
  cmd=[cc,'-std=gnu11','-fstack-protector-strong',*flags,'-I',str(base),'-DSTORAGE_HEADER='+json.dumps(str(base/'storage.h')),'-DEXPECT_FAST='+str(fast),'-DEAGER_MAIN='+str(eager),str(r/'whole-header.c'),'-lm','-ldl','-pthread','-o',str(binary)]
  p=subprocess.run(cmd,capture_output=True,text=True);row={'label':label,'profile':name,'compile':{'command':cmd,'exit':p.returncode,'stderr':p.stderr[-2000:]}}
  report['rows'].append(row)
  if p.returncode==0:
   env=os.environ.copy();env['ASAN_OPTIONS']='detect_stack_use_after_return=0:detect_leaks=0';q=subprocess.run([str(binary)],capture_output=True,text=True,env=env,timeout=20);row['run']={'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr[-2000:]};row['passed']=q.returncode==0 and q.stdout=='native stack position ok\n' and q.stderr==''
   if row['passed'] and 'SAN' not in name:
    asm=subprocess.check_output(['objdump','-d','--no-show-raw-insn','-Mintel',str(binary)],text=True);checks={}
    for fn in ['scalar_guard','real_buffer','g_stack_check_init']:
     m=re.search(r'^[0-9a-f]+ <'+fn+r'(?:\.constprop\.\d+)?>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)',asm,re.S|re.M)
     assert m,fn
     checks[fn]='fs:0x28' in m[1]
    row['structure']={'scalar_canary_matches_expected':checks['scalar_guard']==(not bool(fast)),'real_escaped_buffer_canary_retained':checks['real_buffer'],'cold_pthread_initializer_canary_retained':checks['g_stack_check_init']};row['passed'] &= all(row['structure'].values())
  else:row['passed']=False
  print(prefix,row['passed'],flush=True)
report['status']='passed' if all(x['passed'] for x in report['rows']) else 'failed'
(r/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(report['status'],len(report['rows']))
