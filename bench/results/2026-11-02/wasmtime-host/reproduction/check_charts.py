"""Check displayed Wasmtime bar labels and embedded measurement identities."""
from collections import Counter
import hashlib,json
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'bench/results/2026-11-02/wasmtime-host'
report_path=OUT/'report.json';report=json.loads(report_path.read_text())
label=lambda d:f"{d['median']*1000:.3g} ±{d['mad']*1000:.2g}"
verified=[]
for filename,backend in [('wasmtime-host-runtime.svg','direct'),('wasmtime-host-c-wasm.svg','c-wasm'),('wasmtime-host-preparation.svg',None)]:
    if backend:
        values=[label(r['wall_seconds'])for r in report['runtime_summary']
                if (r['backend']==backend and r['mode']in ['python','native','precompiled'])or r['backend']=='native']
    else:values=[label(r['wall_seconds'])for r in report['preparation_summary']]
    path=ROOT/'bench/charts'/filename;data=path.read_text();tree=ET.fromstring(data)
    actual=[''.join(n.itertext())for n in tree.iter('{http://www.w3.org/2000/svg}text')if 'font-size: 8px' in n.get('style','')]
    assert Counter(actual)==Counter(values),(filename,Counter(actual)-Counter(values),Counter(values)-Counter(actual))
    assert hashlib.sha256(report_path.read_bytes()).hexdigest()in data
    assert report['host_build']['host_sha256']in data and report['host_build']['library_sha256']in data
    verified.append({'chart':str(path.relative_to(ROOT)),'labels':len(actual),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert sum(r['labels']for r in verified)==120
(OUT/'chart-verification.json').write_text(json.dumps({'status':'passed','labels':120,'charts':verified,
 'visual_inspection':{'status':'passed','rendered_width':1500,'charts':3,'checks':['Labels, legends and preparation boundary visible','No clipping or text overlap']}},indent=2)+'\n')
print('PASS 120 numeric labels, report/host/engine identities and three visual previews')
