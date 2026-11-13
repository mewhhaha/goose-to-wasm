#!/usr/bin/env python3
"""Run upstream Goose tests against this compiler and classify the results.

Feeds docs/FEATURES.md: results.jsonl and results.tsv in --output-dir hold the per-test classification, and --summarize prints the roll-up.
Example: python3 tests/upstream_inventory.py --upstream build/upstream-goose --output-dir build/feature-inventory --jobs 4
"""
import argparse, collections, csv, json, os, re, shutil, subprocess, sys, threading, time, hashlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIN_DEFAULT = '2e2bedef5b980bf013cac5aaa0095bfea64e5569'

# Set by configure() after argument parsing; the job code below reads them as globals.
UP = OUT = GOOSE = PIN = JOBS = LIMIT = ONLY = STD = work = cp = logs = None
status = {}

def configure(args):
    global UP, OUT, GOOSE, PIN, JOBS, LIMIT, ONLY, STD, work, cp, logs, status
    UP = Path(args.upstream).resolve()
    OUT = Path(args.output_dir).resolve()
    GOOSE = Path(args.compiler).resolve()
    PIN = args.pin
    JOBS = args.jobs
    LIMIT = args.limit
    ONLY = args.only
    work = OUT / os.environ.get('WORKDIR', 'work')
    cp = OUT / 'upstream'  # copy of test/, stdlib/, samples/ used as cwd and --stdlib
    if not cp.exists():
        cp.mkdir(parents=True)
        for d in ('test', 'stdlib', 'samples'):
            shutil.copytree(UP / d, cp / d)
    STD = Path(args.stdlib).resolve() if args.stdlib else cp / 'stdlib'
    work.mkdir(exist_ok=True)
    logs = OUT / 'logs'
    logs.mkdir(exist_ok=True)
    status = {}
    for line in git('diff', '--name-status', PIN + '..HEAD', '--', 'test', 'samples').splitlines():
        s, p = line.split('\t')[0], line.split('\t')[-1]
        status[p] = s[0]

def git(*a):
    return subprocess.run(['git', '-C', str(UP), *a], capture_output=True, text=True).stdout

def pin_status(rel):
    s = status.get(rel)
    return {'A': 'new', 'M': 'modified', None: 'pinned'}.get(s, s)

FS = re.compile(r'\b(read_file|write_file|write_file_atomic|append_file|file_exists|delete_file|rename_file|make_dir|is_dir|delete_dir|list_dir|gs_os_\w+|replace_file|os\.)\b')
fslock = threading.Lock()

def run(cmd, cwd, stdin=None, timeout=60):
    t = time.monotonic()
    try:
        p = subprocess.run([str(c) for c in cmd], cwd=cwd, input=stdin, capture_output=True, timeout=timeout)
        return dict(code=p.returncode, out=p.stdout.decode(errors='replace'), err=p.stderr.decode(errors='replace'), sec=time.monotonic() - t, timeout=False)
    except subprocess.TimeoutExpired as e:
        return dict(code=None, out=(e.stdout or b'').decode(errors='replace'), err=(e.stderr or b'').decode(errors='replace'), sec=time.monotonic() - t, timeout=True)

def first_diag(err):
    for l in err.splitlines():
        m = re.match(r'^\S.*?:\d+(?::\d+)?: (?:error|fatal error): (.*)$', l)
        if m: return m[1]
    for l in err.splitlines():
        if 'error' in l.lower() or 'panic' in l.lower() or 'abort' in l.lower() or 'fail' in l.lower():
            return l.strip()
    return err.strip().splitlines()[0] if err.strip() else ''

def norm(msg):
    msg = re.sub(r"'[^']*'", "'X'", msg)
    msg = re.sub(r'\b\d+\b', 'N', msg)
    return msg[:140]

def error_markers(path):
    return re.findall(r'^// error: (.+)$', path.read_text(errors='replace'), re.M)

def diag_text(err):
    d = []
    for line in err.splitlines():
        m = (re.match(r'^\S.*:\d+(?::\d+)?: error: (.*)$', line) or
             re.match(r'^  (in (?:fn|thread_fn) .*) instantiated from .*:\d+$', line) or
             re.match(r'^  candidate \S+ at .*?:\d+: (.*)$', line))
        if m: d.append(m[1])
        elif line.startswith('  in const for '): d.append(line.strip())
        elif line == 'program needs exactly one global fn main()': d.append(line)
    return '\n'.join(d)

def first_line(p):
    with open(p, errors='replace') as f: return f.readline()

def stage_fail(rec, src, extra, r):
    """classify failed emit: parse / check / codegen"""
    rec['diag'] = first_diag(r['err']); rec['diag_norm'] = norm(rec['diag'])
    if r['timeout']:
        rec['phase'] = 'timeout-compile'; return
    if r['code'] is not None and r['code'] < 0:
        rec['phase'] = 'crash-compile'; return
    p = run([GOOSE, src, '--parse', '--stdlib', STD], cp, timeout=60)
    if p['code'] != 0:
        rec['phase'] = 'parse'; rec['diag'] = first_diag(p['err']); rec['diag_norm'] = norm(rec['diag']); return
    c = run([GOOSE, src, '--check', '--stdlib', STD] + extra, cp, timeout=60)
    if c['code'] != 0:
        rec['phase'] = 'check'; rec['diag'] = first_diag(c['err']); rec['diag_norm'] = norm(rec['diag']); return
    rec['phase'] = 'codegen'

def positive(cat, f, idx, lock_fs=True):
    rel = str(f.relative_to(UP))
    name = f.stem
    rec = dict(test=rel, category=cat, pin=pin_status(rel), kind='run')
    line = first_line(f)
    d = work / f'{cat}__{name}'
    d.mkdir(parents=True, exist_ok=True)
    src = cp / rel
    cwd = cp
    parse_only = 'parse-only' in line
    native_mod = cat in ('audio', 'gfx', 'physics', 'ui')
    if parse_only:
        rec['kind'] = 'parse-only'
        r = run([GOOSE, src, '--parse', '--stdlib', STD], cwd)
        rec['status'] = 'pass' if r['code'] == 0 else 'fail'
        if rec['status'] == 'fail':
            rec['phase'] = 'parse'; rec['diag'] = first_diag(r['err']); rec['diag_norm'] = norm(rec['diag'])
        return rec
    if cat == 'samples':
        sname = re.sub(r'^\d+_', '', name)
        expf = cp / 'samples/expected' / f'{sname}.out'
        cwd = cp / 'samples'
        argf = cp / 'samples/data' / f'{sname}.args'
        inf = cp / 'samples/data' / f'{sname}.stdin'
        pargs = argf.read_text().split() if argf.exists() else []
        stdin = inf.read_bytes() if inf.exists() else None
        hdr = cp / 'samples' / f'{sname}.h'
    else:
        expf = cp / 'test/expected' / f'{name}.out'
        pargs = []; stdin = None; hdr = None
    aborts = (cp / 'test/expected' / f'{name}.aborts').exists() if cat != 'samples' else False
    stderr_markers = []
    sf = cp / 'test/expected' / f'{name}.stderr'
    if sf.exists() and cat != 'samples':
        stderr_markers = [l.strip() for l in sf.read_text(errors='replace').splitlines() if l.strip()]
    defines = ['-D' + x for x in re.findall(r'^// runtime-define: (\w+=\w+)$', line, re.M)]
    extra = ['--debug'] if any('GS_DEBUG=1' in x for x in defines) else []
    if hdr is not None and hdr.exists(): extra = ['--include', str(hdr)]
    cfile = d / 'program.c'
    if cfile.exists(): cfile.unlink()
    r = run([GOOSE, src, '--target', 'native', '--stdlib', STD, '-O0', '--standalone', *extra, '-o', cfile], cwd, timeout=60)
    (d / 'compile.log').write_text(r['out'] + r['err'])
    rec['compile_sec'] = round(r['sec'], 2)
    if r['code'] != 0 or not cfile.is_file():
        rec['status'] = 'fail'; stage_fail(rec, src, extra, r); return rec
    if native_mod:
        rec['kind'] = 'native-module-emit-only'; rec['status'] = 'pass'; return rec
    binary = d / 'program'
    cc = run(['gcc', '-std=gnu11', '-O0', *defines, cfile, '-lm', '-ldl', '-pthread', '-o', binary], cwd, timeout=240)
    (d / 'cc.log').write_text(cc['out'] + cc['err'])
    if cc['code'] != 0:
        rec['status'] = 'fail'; rec['phase'] = 'c-compile-error' if not cc['timeout'] else 'timeout-cc'
        m = [l for l in cc['err'].splitlines() if 'error' in l]
        rec['diag'] = re.sub(r'^.*?program\.c:\d+:\d+: ', '', m[0]) if m else cc['err'][:200]
        rec['diag_norm'] = norm(rec['diag']); return rec
    uses_fs = FS.search(f.read_text(errors='replace')) is not None
    def go():
        return run([binary, *pargs], cwd, stdin=stdin, timeout=60)
    if uses_fs or cat == 'samples':
        with fslock: o = go()
    else:
        o = go()
    (d / 'run.out').write_text(o['out']); (d / 'run.err').write_text(o['err'])
    rec['run_sec'] = round(o['sec'], 2)
    if o['timeout']:
        rec['status'] = 'fail'; rec['phase'] = 'timeout-run'; return rec
    if o['code'] is not None and o['code'] < 0 and not aborts:
        rec['status'] = 'fail'; rec['phase'] = 'crash-run'; rec['diag'] = f'signal {-o["code"]}'; rec['diag_norm'] = rec['diag']; return rec
    if not expf.exists():
        rec['status'] = 'nogold'; rec['phase'] = 'no-expected-output'; rec['exit'] = o['code']; return rec
    want = expf.read_bytes().decode(errors='replace').replace('\r\n', '\n').rstrip('\n')
    got = o['out'].replace('\r\n', '\n').rstrip('\n')
    ok_exit = (o['code'] != 0) if aborts else (o['code'] == 0)
    ok_err = all(m in o['err'] for m in stderr_markers) if (stderr_markers or aborts) else True
    mu = re.search(r'undefined symbol: (\w+)', o['err'])
    if mu and got != want:
        rec['status'] = 'fail'; rec['phase'] = 'missing-native-symbol'; rec['exit'] = o['code']
        rec['diag'] = 'undefined symbol: ' + mu[1]; rec['diag_norm'] = rec['diag']; return rec
    if got == want and ok_exit and ok_err:
        rec['status'] = 'pass'
    else:
        rec['status'] = 'fail'
        rec['phase'] = 'wrong-output' if got != want else ('wrong-exit' if not ok_exit else 'wrong-stderr')
        rec['exit'] = o['code']
        rec['diag'] = first_diag(o['err']) if o['err'] else ''
        rec['diag_norm'] = norm(rec['diag'])
        import difflib
        dl = list(difflib.unified_diff(want.splitlines(), got.splitlines(), 'want', 'got', lineterm='', n=0))
        rec['diff_head'] = dl[:8]
    return rec

def negative(cat, f):
    rel = str(f.relative_to(UP))
    rec = dict(test=rel, category=cat, pin=pin_status(rel), kind='must-fail')
    action = '--parse' if cat == 'errors' else '--check'
    r = run([GOOSE, cp / rel, action, '--stdlib', STD] + ([] if cat == 'errors' else []), cp, timeout=60)
    d = work / f'{cat}__{f.stem}'; d.mkdir(parents=True, exist_ok=True)
    (d / 'log').write_text(r['out'] + r['err'])
    rec['sec'] = round(r['sec'], 2)
    markers = error_markers(f)
    rec['diag'] = first_diag(r['err']); rec['diag_norm'] = norm(rec['diag'])
    if r['timeout']:
        rec['status'] = 'fail'; rec['phase'] = 'timeout'; return rec
    if r['code'] is not None and r['code'] < 0:
        rec['status'] = 'fail'; rec['phase'] = 'crash'; rec['diag'] = f'signal {-r["code"]}'; return rec
    if r['code'] == 0:
        rec['status'] = 'fail'; rec['phase'] = 'accepted'; rec['diag'] = ''; rec['diag_norm'] = ''; return rec
    if r['code'] != 1 or ': error:' not in r['err']:
        rec['status'] = 'fail'; rec['phase'] = 'abnormal-exit'; rec['exit'] = r['code']; return rec
    dt = diag_text(r['err'])
    missing = [m for m in markers if m not in dt]
    rec['marker_match'] = bool(markers) and not missing
    if not rec['marker_match']: rec['missing_markers'] = missing[:3]
    rec['status'] = 'pass'
    if cat != 'errors':
        pr = run([GOOSE, cp / rel, '--parse', '--stdlib', STD], cp, timeout=60)
        if pr['code'] != 0:
            rec['status'] = 'fail'; rec['phase'] = 'rejected-at-parse'
            rec['diag'] = first_diag(pr['err']); rec['diag_norm'] = norm(rec['diag'])
    return rec

def run_jobs():
    jobs = []
    pos_cats = ['codegen', 'lifetimes', 'optimizer', 'runtime', 'stdlib', 'storage', 'syntax', 'threads', 'typing', 'packages', 'audio', 'gfx', 'physics', 'ui']
    for c in pos_cats:
        for f in sorted((UP / 'test' / c).glob('*.goose')):
            if f.name == 'lexer_tokens.goose': continue
            if c in ('audio','gfx','physics','ui') and error_markers(f):
                jobs.append(('neg', 'errors_tc', f)); continue
            jobs.append(('pos', c, f))
    for f in sorted((UP / 'samples').glob('*.goose')):
        jobs.append(('pos', 'samples', f))
    for f in sorted((UP / 'test/errors').glob('*.goose')): jobs.append(('neg', 'errors', f))
    for f in sorted((UP / 'test/errors_tc').glob('*.goose')): jobs.append(('neg', 'errors_tc', f))
    for f in sorted((UP / 'test/errors_tc/recovery').glob('*.goose')): jobs.append(('neg', 'errors_tc_recovery', f))
    if ONLY: jobs = [j for j in jobs if re.search(ONLY, str(j[2]))]
    if LIMIT is not None: jobs = jobs[:LIMIT]
    if os.environ.get('RETEST'):
        keep = set(Path(os.environ['RETEST']).read_text().split())
        jobs = [j for j in jobs if str(j[2].relative_to(UP)) in keep]
    resf = OUT / (os.environ.get('OUTNAME') or ('results.jsonl' if not ONLY and not LIMIT else 'results-partial.jsonl'))
    resf.write_text('')
    lock = threading.Lock(); n = [0]
    def do(j):
        try:
            rec = positive(j[1], j[2], 0) if j[0] == 'pos' else negative(j[1], j[2])
        except Exception as e:
            rec = dict(test=str(j[2].relative_to(UP)), category=j[1], status='fail', phase='harness-error', diag=repr(e))
        with lock:
            with resf.open('a') as fh: fh.write(json.dumps(rec) + '\n')
            n[0] += 1
            if n[0] % 100 == 0: print(n[0], '/', len(jobs), flush=True)
    with ThreadPoolExecutor(JOBS) as ex: list(ex.map(do, jobs))
    print('done', len(jobs))

def summarize(out):
    # Folded in from analyze.py: reads an existing results file, writes results.tsv, prints the summary.
    resf = out / 'results.jsonl'
    if not resf.exists() and (out / 'results-partial.jsonl').exists():
        resf = out / 'results-partial.jsonl'
    rs = [json.loads(l) for l in open(resf)]
    gaps = {c for c, l in json.load(open(ROOT / 'tests/conformance/known-gaps.json'))['gaps'] if c.startswith('upstream/')}
    def gid(r):
        p = r['test'].replace('test/', '').replace('.goose', '')
        return 'upstream/' + p
    for r in rs:
        r['known_gap'] = gid(r) in gaps
        r['in_pinned_corpus'] = None
    cases = {x['id'] for x in json.load(open(ROOT / 'tests/conformance/cases.json'))['cases'] if x['id'].startswith('upstream/')}
    for r in rs: r['in_pinned_corpus'] = gid(r) in cases
    cols = ['test', 'category', 'pin', 'kind', 'status', 'phase', 'diag', 'known_gap', 'in_pinned_corpus', 'marker_match', 'compile_sec', 'run_sec', 'sec']
    with open(out / 'results.tsv', 'w') as f:
        w = csv.writer(f, delimiter='\t'); w.writerow(cols)
        for r in sorted(rs, key=lambda r: (r['category'], r['test'])):
            w.writerow([str(r.get(c, '')).replace('\t', ' ').replace('\n', ' ') for c in cols])
    print(len(rs))
    print('cat pin: pass/total')
    for cat in sorted({r['category'] for r in rs}):
        row = []
        for pin in ('pinned', 'modified', 'new'):
            t = [r for r in rs if r['category'] == cat and r['pin'] == pin]
            row.append(f"{pin}={sum(r['status'] == 'pass' for r in t)}/{len(t)}")
        print(f'{cat:20s}', *row)
    for pin in ('pinned', 'modified', 'new'):
        t = [r for r in rs if r['pin'] == pin]; print(pin, sum(r['status'] == 'pass' for r in t), len(t))
    f = [r for r in rs if r['status'] != 'pass']
    print('fail phases', collections.Counter(r.get('phase') for r in f))
    print('failures that are known gaps', sum(r['known_gap'] for r in f), 'of', len(f), '; pinned-corpus failures not in known-gaps:', [r['test'] for r in f if r['in_pinned_corpus'] and not r['known_gap'] and r['kind'] == 'run'][:20])

def main(argv=None):
    ap = argparse.ArgumentParser(description='Run upstream Goose tests against this compiler and classify the results.')
    ap.add_argument('--upstream', help='path to an upstream Goose checkout (its test/, stdlib/ and samples/ are used); required unless --summarize')
    ap.add_argument('--compiler', default=str(ROOT / 'build/bin/goose'), help='goose compiler binary (default: %(default)s)')
    ap.add_argument('--output-dir', required=True, help='where results, logs and the stdlib/test copy are written')
    ap.add_argument('--pin', default=PIN_DEFAULT, help='upstream commit the corpus is diffed against (default: %(default)s, the conformance pin in tests/conformance/cases.json)')
    ap.add_argument('--jobs', type=int, default=4, help='parallel test jobs (default: %(default)s)')
    ap.add_argument('--limit', type=int, default=None, help='run only the first N matching tests')
    ap.add_argument('--only', default='', help='regex; only tests whose path matches it are run')
    ap.add_argument('--stdlib', default=None, help='stdlib directory passed to goose (default: the stdlib copy in --output-dir)')
    ap.add_argument('--summarize', action='store_true', help='print the summary of an existing results file in --output-dir and exit, without running tests')
    args = ap.parse_args(argv)
    if args.summarize:
        summarize(Path(args.output_dir).resolve())
        return
    if args.upstream is None:
        ap.error('--upstream is required unless --summarize is given')
    configure(args)
    run_jobs()

if __name__ == '__main__':
    main()
