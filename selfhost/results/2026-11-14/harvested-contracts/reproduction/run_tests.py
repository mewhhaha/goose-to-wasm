#!/usr/bin/env python3
"""Run each tests/test_*.py module under unittest; record exit, counts and log."""
import json, os, pathlib, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PY = '/home/jacobt/src/goose-to-wasm/.venv/bin/python'
COMPILER = os.environ.get('HARVEST_COMPILER', '/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a636162323a6482dc/build/q-abandon/bootstrap/bin/goose')
LOGS = HERE / os.environ.get('HARVEST_LOGS', 'unit-logs')
LOGS.mkdir(exist_ok=True)
modules = sys.argv[1:] or sorted(p.stem for p in (ROOT / 'tests').glob('test_*.py'))


def one(module):
    start = time.monotonic()
    env = dict(os.environ, GOOSE_COMPILER=COMPILER, PYTHONPATH=str(ROOT / 'tests'))
    try:
        r = subprocess.run([PY, '-m', 'unittest', 'tests.' + module], cwd=ROOT, env=env,
                           capture_output=True, timeout=1200, stdin=subprocess.DEVNULL)
        text = (r.stdout + r.stderr).decode(errors='replace')
        code = r.returncode
    except subprocess.TimeoutExpired as e:
        text = ((e.stdout or b'') + (e.stderr or b'')).decode(errors='replace') + '\nTIMEOUT'
        code = 'timeout'
    (LOGS / (module + '.log')).write_text(text)
    ran = re.findall(r'^Ran (\d+) test', text, re.M)
    tail = re.findall(r'^(OK.*|FAILED.*)$', text, re.M)
    row = {'module': module, 'exit': code, 'ran': int(ran[-1]) if ran else None, 'result': tail[-1] if tail else None,
           'seconds': round(time.monotonic() - start, 1)}
    print(json.dumps(row), flush=True)
    return row


with ThreadPoolExecutor(4) as pool:
    rows = list(pool.map(one, modules))
(LOGS / 'results.json').write_text(json.dumps(rows, indent=1) + '\n')
