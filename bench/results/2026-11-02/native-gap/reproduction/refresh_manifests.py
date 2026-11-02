"""Refresh final editorial/derived artifact hashes without changing archived samples."""
import gzip
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
for name in ['native-gap','compact-examples']:
    out=ROOT/'bench/results/2026-11-02'/name
    map_path=out/'archive-path-map.json.gz'
    data=json.loads(gzip.decompress(map_path.read_bytes()))
    digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
    for entry in data['artifacts']:
        if 'artifact' not in entry or 'member' in entry:
            continue
        artifact=out/entry['artifact']
        if not artifact.is_file():
            continue
        if entry['artifact']=='differential.json.gz':
            entry.pop('sha256',None)
            entry['source_sha256']=digest(ROOT/'build/native-gap/differential/report.json')
            entry['artifact_sha256']=digest(artifact)
        if 'artifact_sha256' in entry:
            entry['artifact_sha256']=digest(artifact)
        elif 'sha256' in entry:
            entry['sha256']=digest(artifact)
        if entry['artifact']=='README.md' and name=='native-gap':
            entry['source']='Editorial README using the linked retained reports'
    if name=='native-gap':
        members={(entry.get('artifact'),entry.get('member')) for entry in data['artifacts']}
        chart_inputs=list((ROOT/'bench/charts').glob('*.svg'))+[ROOT/'bench/charts.py',ROOT/'bench/example_charts.py']
        for source in sorted(chart_inputs):
            member=source.relative_to(ROOT).as_posix()
            if ('charts.tar.gz',member) not in members:
                data['artifacts'].append({'source':member,'artifact':'charts.tar.gz','member':member,'sha256':digest(source)})
    known={entry.get('artifact') for entry in data['artifacts'] if 'member' not in entry}
    for file in sorted(out.rglob('*')):
        if not file.is_file() or file.name in ['SHA256.json','archive-path-map.json.gz']:
            continue
        relative=file.relative_to(out).as_posix()
        if relative not in known:
            data['artifacts'].append({'source':'Final derived evidence or retained reproduction source',
                                      'artifact':relative,'artifact_sha256':digest(file)})
    with map_path.open('wb') as target:
        with gzip.GzipFile(filename='',mode='wb',fileobj=target,mtime=0) as compressed:
            compressed.write((json.dumps(data,indent=2)+'\n').encode())
    files={file.relative_to(out).as_posix():digest(file) for file in sorted(out.rglob('*'))
           if file.is_file() and file.name!='SHA256.json'}
    (out/'SHA256.json').write_text(json.dumps(files,indent=2)+'\n')
print('Refreshed both final archive maps and recursive checksum manifests')
