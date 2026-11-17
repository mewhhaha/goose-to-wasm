#!/usr/bin/env python3
"""hotlines.py FUNCTION [N]: the hottest instructions of FUNCTION in build/exp/prof.exe's last profile, with the three before each."""
import struct, subprocess, collections, bisect, json, sys
exe='build/exp/prof.exe'; fn=sys.argv[1]; N=int(sys.argv[2]) if len(sys.argv)>2 else 12
syms=[]
for line in subprocess.run(['nm','-n','--defined-only',exe],capture_output=True,text=True).stdout.splitlines():
    p=line.split()
    if len(p)==3 and p[1] in 'tTwW': syms.append((int(p[0],16),p[2]))
addrs=[a for a,_ in syms]
names={'g_fn%d'%f['id']:f['name'] for f in json.load(open(exe+'.stats.json'))['function_names']}
def sym(v):
    i=bisect.bisect_right(addrs,v)-1
    return syms[i]
data=open('build/tmp/sp/prof.out','rb').read()
pcs=collections.Counter()
for v,c1,c2 in struct.iter_unpack('<QQQ',data[:len(data)//24*24]):
    if v!=0xffffffffffffffff and names.get(sym(v)[1],sym(v)[1])==fn: pcs[v]+=1
top=pcs.most_common(N)
start=sym(top[0][0])[0]
print(fn,'at',hex(start),'samples',sum(pcs.values()))
dis=subprocess.run(['objdump','-d','--no-show-raw-insn','--start-address',hex(start),'--stop-address',hex(start+0x8000),exe],capture_output=True,text=True).stdout.splitlines()
idx={}
for i,l in enumerate(dis):
    try: idx[int(l.strip().split(':')[0],16)]=i
    except: pass
lines=subprocess.run(['addr2line','-e',exe]+[hex(v) for v,_ in top],capture_output=True,text=True).stdout.split('\n')
for (v,n),ln in zip(top,lines):
    i=idx.get(v)
    print(n, hex(v-start), ln.split(':')[-1], '|', ' ; '.join(x.split('\t',1)[-1].strip() for x in dis[max(0,i-3):i+1]) if i else '?')
