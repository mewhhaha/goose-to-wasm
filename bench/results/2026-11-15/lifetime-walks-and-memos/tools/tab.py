import sys
def load(path):
    rows=[]; t0=None
    for line in open(path, errors='replace'):
        if not line.startswith('LIFEPROG'): continue
        parts=line.split(); tag=parts[1]
        try: d={k:int(v) for k,v in (kv.split('=') for kv in parts[2:])}
        except Exception: continue
        if tag=='pass_begin' and t0 is None: t0=d['ms']
        d['tag']=tag; d['s']=(d['ms']-(t0 or d['ms']))/1000
        rows.append(d)
    return rows
step=int(sys.argv[2]) if len(sys.argv)>2 else 5000
for path in sys.argv[1:2]:
    rows=load(path)
    for d in rows:
        if d['tag']!='frames' or d['frames']%step==0 or d is rows[-1]:
            print('%-11s p%d s=%7.1f frames=%7d effects=%8d sets=%8d alts=%9d roots=%8d items=%8d act=%8d set_index=%9d' % (d['tag'],d['pass'],d['s'],d['frames'],d['effects'],d['sets'],d['alts'],d['roots'],d['items'],d['activations'],d.get('set_index',0)))
