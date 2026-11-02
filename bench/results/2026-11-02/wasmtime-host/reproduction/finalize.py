"""Finish the host evidence with chart sources and final checksum manifests."""
import gzip,hashlib,json,tarfile,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'bench/results/2026-11-02/wasmtime-host'
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
p=OUT/'qualification-summary.json';d=json.loads(p.read_text())
for old,new in [('python_host_bench_observations','benchmark_runtime_observations'),
                ('python_host_preparations','benchmark_preparation_observations'),
                ('qualification_report_sha256','qualification_report_uncompressed_sha256')]:
    if old in d:d[new]=d.pop(old)
d['qualification_report_compressed_sha256']=digest(OUT/'qualification-report.json.gz')
p.write_text(json.dumps(d,indent=2)+'\n')
repro=OUT/'reproduction';repro.mkdir(exist_ok=True)
for source in [ROOT/'bench/wasmtime_host.py',ROOT/'bench/qualify_wasmtime_host.py',
               ROOT/'bench/wasmtime_host_charts.py',ROOT/'bench/example_charts.py',
               ROOT/'scripts/build_wasmtime_host.py',ROOT/'build/wasmtime-host/qualify_boundaries.py',
               ROOT/'build/wasmtime-host/check_charts.py',ROOT/'build/wasmtime-host/package.py',Path(__file__).resolve()]:
    shutil.copy2(source,repro/source.name)
archive=OUT/'charts.tar.gz'
chart_sources=list(sorted((ROOT/'bench/charts').glob('wasmtime-host-*.svg')))+[ROOT/'bench/wasmtime_host_charts.py',ROOT/'bench/example_charts.py',ROOT/'build/wasmtime-host/check_charts.py']
# Rewrite a small deterministic chart snapshot; measured samples are untouched.
rewrite=not archive.exists()
if not rewrite:
    with tarfile.open(archive)as tar:
        rewrite=any(hashlib.sha256(tar.extractfile(source.relative_to(ROOT).as_posix()).read()).hexdigest()!=digest(source)for source in chart_sources)
if rewrite:
    with tarfile.open(archive,'w:gz',compresslevel=6)as tar:
        for source in chart_sources:tar.add(source,arcname=source.relative_to(ROOT).as_posix())
map_path=OUT/'archive-map.json.gz';entries=json.loads(gzip.decompress(map_path.read_bytes()))
entries=[entry for entry in entries if entry.get('archive')!='charts.tar.gz']
for source in chart_sources:
    entries.append({'source':source.relative_to(ROOT).as_posix(),'archive':'charts.tar.gz',
                    'member':source.relative_to(ROOT).as_posix(),'sha256':digest(source),'phase':'post-measurement'})
with map_path.open('wb')as output:
    with gzip.GzipFile(filename='',mode='wb',fileobj=output,mtime=0)as zipped:
        zipped.write(json.dumps(entries,sort_keys=True,separators=(',',':')).encode())
checksums={p.relative_to(OUT).as_posix():digest(p)for p in sorted(OUT.rglob('*'))if p.is_file()and p.name!='SHA256.json'}
(OUT/'SHA256.json').write_text(json.dumps(checksums,indent=2,sort_keys=True)+'\n')
pointer={'schema':'goose-wasmtime-host-latest-v1','report':'2026-11-02/wasmtime-host/report.json','sha256':digest(OUT/'report.json')}
(ROOT/'bench/results/wasmtime-host-latest.json').write_text(json.dumps(pointer,indent=2)+'\n')
print('Final host metadata, chart snapshot and',len(checksums),'file hashes updated')
