import os, sys, subprocess, resource, time, random, json, statistics
S=os.path.dirname(os.path.abspath(__file__))
R='/home/jacobt/src/goose-to-wasm'
commits=[l.strip() for l in open(S+'/all.txt') if os.path.exists(f'{S}/build-{l.strip()}/bin/goose')]
rounds=int(sys.argv[1]); progs=sys.argv[2].split(','); phases=sys.argv[3].split(',')
P={'empty':S+'/work/empty.goose'}
for n in ['sorting','functions','squares','tour']: P[n]=f'{R}/examples/{n}.goose'
def cmd(c,ph,prog):
    g=f'{S}/build-{c}/bin/goose'; sd=f'{S}/src-{c}/stdlib'
    base=[g,P[prog],'--stdlib',sd]
    if ph=='check': return base+['--check']
    if ph=='wasm': return base+['-O2','--target','wasm-direct','--wasm-initial-pages','16','--wasm-max-pages','256','-o',S+'/work/out.wasm']
    if ph=='native': return base+['-O2','--target','native','-o',S+'/work/out.c']
def run(c):
    r0=resource.getrusage(resource.RUSAGE_CHILDREN); t=time.perf_counter()
    p=subprocess.run(c,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    w=time.perf_counter()-t; r1=resource.getrusage(resource.RUSAGE_CHILDREN)
    if p.returncode: raise SystemExit(f'fail {c} {p.stderr[:300]}')
    return w*1e3,((r1.ru_utime-r0.ru_utime)+(r1.ru_stime-r0.ru_stime))*1e3,r1.ru_minflt-r0.ru_minflt
res={}
for prog in progs:
  for ph in phases:
    d={c:[] for c in commits}
    for r in range(rounds):
        o=commits[:]; random.shuffle(o)
        for c in o: d[c].append(run(['taskset','-c','7']+cmd(c,ph,prog)))
    for c in commits:
        v=d[c]; res[f'{prog}|{ph}|{c}']=[statistics.median(x[i] for x in v) for i in range(3)]
json.dump(res,open(sys.argv[4],'w'))
