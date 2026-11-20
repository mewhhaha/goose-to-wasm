"""Plot full-check instruction savings and the measured cost of a cached self-build."""
import gzip
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter

directory = Path(__file__).resolve().parent
with gzip.open(directory / 'capture-checks.json.gz', 'rt') as stream:
    cases = json.load(stream)['runs']['scale']['cases']
rebuild = json.loads((directory / 'rebuild-summary.json').read_text())['current']
plt.rcParams.update({'svg.hashsalt': 'goose-global-captures', 'svg.fonttype': 'none', 'font.size': 10})
fig, (checks, own) = plt.subplots(1, 2, figsize=(9.3, 3.9), width_ratios=[1.5, 1], layout='constrained')
fig.suptitle('Lifetime checks and compiler rebuilds', x=0.025, ha='left', fontsize=16, weight='bold')

widths = sorted({case['width'] for case in cases})
for shape, label, color, offset in [('sparse', 'Reads two globals', '#137c74', -0.19),
                                     ('dense', 'Reads every global', '#496b95', 0.19)]:
    savings = []
    for width in widths:
        samples = next(case['rows'] for case in cases if case['shape'] == shape and case['width'] == width)
        before, after = [median(r['counters']['instructions']['value'] for r in samples if r['compiler'] == key)
                         for key in ('before', 'after')]
        savings.append(100 * (1 - after / before))
    bars = checks.bar([i + offset for i in range(len(widths))], savings, 0.36, color=color, label=label)
    checks.bar_label(bars, labels=[f'{v:.1f}%' for v in savings], padding=3, fontsize=9)

checks.set_title('Fewer instructions per compile check', loc='left', fontsize=12)
checks.set_xticks(range(len(widths)), labels=widths)
checks.set_xlabel('Globals in the generated program')
checks.yaxis.set_major_formatter(PercentFormatter(xmax=100))
checks.set_ylim(0, 56)
checks.legend(loc='upper left', frameon=False)

times = [rebuild['medians'][k]['wall_seconds'] for k in ('native', 'wasm')]
ratio = rebuild['paired']['wasm / native']['wall_seconds']['median']
bars = own.bar(['Native Goose', 'Cached Wasmtime'], times, width=.60, color=['#445665', '#137c74'])
own.bar_label(bars, labels=[f'{v:.2f} s' for v in times], padding=4, weight='bold')
own.set_title('Rebuilding the compiler itself', loc='left', fontsize=12)
own.set_ylabel('Elapsed seconds')
own.set_ylim(0, max(times) * 1.25)
own.set_xlabel(f'{rebuild["rounds"]} paired rebuilds · median ratio {ratio:.2f}×')
for ax in (checks, own):
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)
    ax.set_axisbelow(True)
    ax.grid(axis='y', color='#dce2e7', linewidth=.8)
fig.savefig(directory / 'capture-cost.png', dpi=150)
path = directory / 'capture-cost.svg'
fig.savefig(path, metadata={'Date': None})
path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines()) + '\n')

profiles = json.loads((directory / 'modules.json').read_text())['profiles']
fig, ax = plt.subplots(figsize=(7.8, 3.3), layout='constrained')
ax.set_title('Compiler download size by release profile', loc='left', fontsize=14, weight='bold')
names = ['fixed', 'balanced', 'size']
for key, label, offset, color in [('bytes', 'Wasm module', -.19, '#496b95'),
                                   ('gzip_bytes', 'Gzip download', .19, '#137c74')]:
    values = [profiles[name][key] / 1e6 for name in names]
    bars = ax.bar([i + offset for i in range(3)], values, .36, label=label, color=color)
    ax.bar_label(bars, labels=[f'{v:.2f} MB' for v in values], padding=3)
ax.set_xticks(range(3), labels=['Direct', 'Balanced', 'Size'])
ax.set_ylabel('Megabytes')
ax.set_ylim(0, 7.4)
ax.legend(loc='upper right', frameon=False)
ax.spines[:].set_visible(False)
ax.tick_params(length=0, pad=5)
ax.set_axisbelow(True)
ax.grid(axis='y', color='#dce2e7', linewidth=.8)
path = directory / 'downloads.svg'
fig.savefig(path, metadata={'Date': None})
path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines()) + '\n')
