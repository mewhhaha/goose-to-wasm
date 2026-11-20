"""Plot artifact sizes and fresh-process rebuild timings from the paired run."""
import gzip
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
data = json.loads((directory / 'rebuilds.json').read_text())
with gzip.open(directory / 'process-counters.json.gz', 'rt') as stream:
    counters = json.load(stream)
keys = ['direct', 'balanced', 'size']
labels = ['Direct', 'Balanced', 'Size']
colors = ['#8897a4', '#257b71', '#3e608c']
plt.rcParams['svg.hashsalt'] = 'goose-compact-releases'
fig, axes = plt.subplots(2, 3, figsize=(11.5, 5.4), layout='constrained')
preparation = counters['cold_preparation']['rows']
panels = [
    ('Compiler module', 'MB', [data['modules'][k]['bytes'] / 1e6 for k in keys]),
    ('Download at gzip -9', 'MB', [data['modules'][k]['gzip_bytes'] / 1e6 for k in keys]),
    ('Cold Wasmtime preparation', 's', [median(r['engine']['compile_instantiate_ns']
        for r in preparation if r['profile'] == k) / 1e9 for k in keys]),
]
for cache, title in [(False, 'Cold project rebuild'), (True, 'Cached project rebuild')]:
    times = [median(r['wall_ns'] for r in data['rows'] if r['profile'] == k and r['cached'] == cache)
             / 1e9 for k in keys]
    panels.append((title, 's', times))
native_comparison = [median(r['wall_ns'] for r in counters['rows'] if r['profile'] == key) / 1e9
                     for key in ('native', 'balanced')]
series = [(labels, colors)] * len(panels)
panels.append(('Cached rebuild vs native¹', 's', native_comparison))
series.append((['Native', 'Balanced'], ['#455863', colors[1]]))
for ax, (title, unit, values), (names, palette) in zip(axes.flat, panels, series, strict=True):
    bars = ax.bar(names, values, color=palette, width=0.62)
    ax.bar_label(bars, labels=[f'{value:.2f}' for value in values], padding=3, fontsize=11)
    ax.set_ylim(0, max(values) * 1.23)
    ax.set_title(title, loc='left', fontweight='bold', fontsize=12)
    ax.set_ylabel(unit)
    ax.spines[:].set_visible(False)
    ax.grid(axis='y', color='#dce2e7', linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(length=0, pad=4)
fig.supxlabel('¹ Independent seven-round comparison on CPU 5. All panels use one core.', fontsize=9)
fig.savefig(directory / 'profiles.png', dpi=145)
svg = directory / 'profiles.svg'
fig.savefig(svg, metadata={'Date': None})
svg.write_text('\n'.join(line.rstrip() for line in svg.read_text().splitlines()) + '\n')
