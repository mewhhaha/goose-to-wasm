"""Check all 193 displayed bar labels and embedded report identities."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
RESULTS = ROOT/'bench/results'
legacy_path = RESULTS/json.loads((RESULTS/'latest.json').read_text())['report']
example_path = RESULTS/json.loads((RESULTS/'examples-latest.json').read_text())['report']
legacy = json.loads(legacy_path.read_text());examples = json.loads(example_path.read_text())
expected = {}
expected['compilation.svg'] = [format(row['wall_seconds']['median']*1000,'.0f') for row in legacy['compile_summary'] if row['track']=='adapted' and row['phase']=='cold']
expected['runtime.svg'] = [format(row['timed_region_seconds']['median'],'.2f') for engine in ['v8','wasmtime'] for row in legacy['runtime_summary'] if row['track']=='adapted' and row['profile']=='run' and row['engine'] in [engine,'native']]

def label(row,metric):
    sample=row[metric]
    return f"{sample['median']*1000:.3g} ±{sample['mad']*1000:.2g}"

expected['examples-compilation.svg'] = [label(row,'wall_seconds') for row in examples['compile_summary']]
for name,metric in [('examples-runtime.svg','process_wall_seconds'),('examples-entry.svg','entry_function_seconds')]:
    expected[name] = [label(row,metric) for engine in ['v8','wasmtime'] for row in examples['runtime_summary'] if row['engine'] in [engine,'native'] and (row['backend']!='native' or name=='examples-runtime.svg')]
verified=[]
for name,values in expected.items():
    path=ROOT/'bench/charts'/name;data=path.read_text();tree=ET.fromstring(data)
    size='font-size: 8.5px' if not name.startswith('examples-') else 'font-size: 8px'
    actual=[''.join(node.itertext()) for node in tree.iter('{http://www.w3.org/2000/svg}text') if size in node.get('style','')]
    assert Counter(actual)==Counter(values),(name,Counter(actual)-Counter(values),Counter(values)-Counter(actual))
    report=example_path if name.startswith('examples-') else legacy_path
    assert hashlib.sha256(report.read_bytes()).hexdigest() in data
    verified.append({'chart':str(path.relative_to(ROOT)),'labels':len(actual),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert sum(row['labels'] for row in verified)==193
out=ROOT/'bench/results/2026-11-02/native-gap/chart-verification.json'
out.write_text(json.dumps({'status':'passed','verified_labels':193,'charts':verified},indent=2)+'\n')
print('PASS',193,'chart labels and all five report identities')
