#!/usr/bin/env python3
"""Generate frozen deterministic compiler-throughput workloads under build/bench-workloads/2026-11-26/.

Workloads:
  1. flat_multi_100k: 16 imported modules + main.goose (~100,000 LOC, 2,000 functions)
  2. flat_single_100k: single main.goose (~100,000 LOC, 2,000 functions)
  3. selfhost_f746c6e: frozen git archive of selfhost/ + stdlib/ at f746c6e

All workloads are pure plain upstream Goose and deterministic (checksummed).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'build/bench-workloads/2026-11-26'


def make_function(fn_id: int, prev_call: str | None) -> str:
    k1 = (fn_id * 31 + 7) & 0xFFFF
    k2 = (fn_id * 17 + 13) & 0xFFFF
    k3 = (fn_id * 53 + 29) & 0xFFFF
    k4 = (fn_id * 11 + 3) & 0xFF
    call_line = f'    acc = acc + {prev_call}(a + {k4}, b ^ {k1});' if prev_call else f'    acc = acc + (a ^ {k1});'
    return f"""fn compute_{fn_id}(a: i64, b: i64) -> i64 {{
    var acc: i64 = a * {k1} + b * {k2} + {k3};
    var x: i64 = a + {k4};
    var y: i64 = b - {k4};
    var s: Pair = Pair {{ lo: x, hi: y, tag: {fn_id & 7} }};
    var buf: i64[8] = [x, y, acc, x + y, x - y, a ^ b, s.lo, s.hi];
    var i: i64 = 0;
    while i < 8 {{
        let v: i64 = buf[i];
        if (v & 1) == 0 {{
            acc = acc + (v * 3) - (i * {k4 + 1});
        }} else {{
            acc = acc ^ (v + {k2}) + i;
        }}
        buf[i] = acc & 0x7FFFFFFF;
        i = i + 1;
    }}
    let m: i64 = match s.tag {{
        0 => buf[0] + buf[7],
        1 => buf[1] - buf[6],
        2 => buf[2] ^ buf[5],
        3 => buf[3] + buf[4],
        4 => (buf[0] + buf[2]) ^ buf[4],
        5 => (buf[1] + buf[3]) - buf[5],
        6 => (buf[2] + buf[6]) + {k1},
        _ => (buf[3] ^ buf[7]) + {k2},
    }};
    acc = acc + m;
    var j: i64 = 0;
    while j < 4 {{
        let p: Pair = Pair {{ lo: acc + j, hi: m - j, tag: j }};
        acc = acc + (p.lo ^ p.hi) + p.tag;
        if acc > 1000000000 {{
            acc = acc - 500000000;
        }} else if acc < -1000000000 {{
            acc = acc + 500000000;
        }}
        j = j + 1;
    }}
    let q: i64 = (buf[0] + buf[1] + buf[2] + buf[3]) ^ (buf[4] + buf[5] + buf[6] + buf[7]);
    acc = (acc + q) & 0x3FFFFFFF;
{call_line}
    return acc & 0x3FFFFFFF;
}}
"""


def write_text(path: Path, text: str) -> tuple[int, str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = text.encode('utf-8')
    path.write_bytes(data)
    return text.count('\n'), hashlib.sha256(data).hexdigest()


def generate_flat_multi(base: Path, num_modules: int = 16, fns_per_mod: int = 140) -> dict:
    total_lines = 0
    files = {}
    common_p = base / 'common.goose'
    lines, sha = write_text(common_p, '// Frozen multi-file throughput shared types\nstruct Pair {\n    lo: i64,\n    hi: i64,\n    tag: i64,\n}\n')
    total_lines += lines
    files[common_p.name] = {'lines': lines, 'sha256': sha}

    for m in range(num_modules):
        parts = [
            f'// Frozen multi-file throughput module {m:02d}\n',
            'import common;\n\n',
        ]
        prev = None
        for f in range(fns_per_mod):
            fn_id = m * fns_per_mod + f
            parts.append(make_function(fn_id, prev))
            prev = f'compute_{fn_id}'
        parts.append(f"""fn entry_{m:02d}(seed: i64) -> i64 {{
    var total: i64 = seed;
    total = (total + compute_{m * fns_per_mod}(seed, seed + 17)) & 0x3FFFFFFF;
    total = (total + compute_{m * fns_per_mod + fns_per_mod - 1}(total, seed + 31)) & 0x3FFFFFFF;
    return total;
}}
""")
        p = base / f'mod_{m:02d}.goose'
        lines, sha = write_text(p, ''.join(parts))
        total_lines += lines
        files[p.name] = {'lines': lines, 'sha256': sha}

    main_parts = ['// Frozen multi-file throughput root\n', 'import common;\n']
    for m in range(num_modules):
        main_parts.append(f'import mod_{m:02d};\n')
    main_parts.append('\nfn main() {\n    var acc: i64 = 12345;\n')
    for m in range(num_modules):
        main_parts.append(f'    acc = (acc + entry_{m:02d}(acc + {m + 1})) & 0x3FFFFFFF;\n')
    main_parts.append('    print(acc);\n}\n')
    p = base / 'main.goose'
    lines, sha = write_text(p, ''.join(main_parts))
    total_lines += lines
    files[p.name] = {'lines': lines, 'sha256': sha}
    return {'modules': num_modules + 2, 'functions': num_modules * (fns_per_mod + 1) + 1,
            'total_lines': total_lines, 'files': files}


def generate_flat_single(base: Path, total_fns: int = 2240) -> dict:
    parts = [
        '// Frozen single-file throughput workload\n',
        'struct Pair {\n    lo: i64,\n    hi: i64,\n    tag: i64,\n}\n\n',
    ]
    prev = None
    for f in range(total_fns):
        # Reset chain every 140 fns to match flat_multi call depth
        if f % 140 == 0:
            prev = None
        parts.append(make_function(f, prev))
        prev = f'compute_{f}'
    parts.append('\nfn main() {\n    var acc: i64 = 12345;\n')
    for m in range(total_fns // 140):
        base_id = m * 140
        parts.append(f'    acc = (acc + compute_{base_id}(acc + {m + 1}, acc + 18 + {m})) & 0x3FFFFFFF;\n')
        parts.append(f'    acc = (acc + compute_{base_id + 139}(acc, acc + 32 + {m})) & 0x3FFFFFFF;\n')
    parts.append('    print(acc);\n}\n')
    p = base / 'main.goose'
    lines, sha = write_text(p, ''.join(parts))
    return {'modules': 1, 'functions': total_fns + 1, 'total_lines': lines,
            'files': {p.name: {'lines': lines, 'sha256': sha}}}


def freeze_selfhost(dest: Path, rev: str = 'f746c6e') -> dict:
    if dest.exists():
        # Verify already frozen
        marker = dest / '.rev'
        if marker.exists() and marker.read_text().strip() == rev and (dest / 'native').exists():
            goose_files = sorted(dest.rglob('*.goose'))
            total_lines = sum(p.read_text().count('\n') for p in goose_files)
            selfhost_lines = sum(p.read_text().count('\n') for p in sorted((dest / 'selfhost').glob('*.goose')))
            return {'rev': rev, 'selfhost_lines': selfhost_lines, 'total_lines': total_lines,
                    'file_count': len(goose_files)}
    dest.mkdir(parents=True, exist_ok=True)
    p1 = subprocess.Popen(['git', 'archive', rev, '--', 'selfhost', 'stdlib', 'native'], cwd=ROOT, stdout=subprocess.PIPE)
    p2 = subprocess.Popen(['tar', '-x', '-C', str(dest)], stdin=p1.stdout)
    assert p1.stdout is not None
    p1.stdout.close()
    rc2 = p2.wait()
    rc1 = p1.wait()
    if rc1 != 0 or rc2 != 0:
        raise SystemExit(f'git archive {rev} failed: rc1={rc1}, rc2={rc2}')
    (dest / '.rev').write_text(rev + '\n')
    goose_files = sorted(dest.rglob('*.goose'))
    total_lines = sum(p.read_text().count('\n') for p in goose_files)
    selfhost_lines = sum(p.read_text().count('\n') for p in sorted((dest / 'selfhost').glob('*.goose')))
    return {'rev': rev, 'selfhost_lines': selfhost_lines, 'total_lines': total_lines,
            'file_count': len(goose_files)}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        'flat_multi_100k': generate_flat_multi(OUT / 'flat_multi_100k'),
        'flat_single_100k': generate_flat_single(OUT / 'flat_single_100k'),
        'selfhost_f746c6e': freeze_selfhost(OUT / 'selfhost_f746c6e'),
    }
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    for k, v in manifest.items():
        print(f"{k}: {v.get('selfhost_lines', v.get('total_lines'))} LOC (total {v['total_lines']})")


if __name__ == '__main__':
    main()
