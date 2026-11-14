#!/usr/bin/env python3
"""Turn the surveyed programs (db.json) into harvest fixtures, conformance rows
and an exclusion manifest.

decisions.json holds the reviewed per-program calls:
  "exclude": reason key, with "note"            excluded from the contract set
  "stderr_contains": [...]                      error row text (our diagnostic)
  "false_accept": "..."                         upstream accepts; a type-error row per the cited rule
  "maximum_pages": {"wasm-direct": N}           Wasm memory a row states
  "gap": cause key, "gap_targets": [...]        rows registered as known gaps
"""
import json, pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FIXTURES = ROOT / 'tests/fixtures/contracts/upstream-differential/harvest'
PREFIX = 'corpus/contracts/upstream-differential/harvest/'
TARGETS = ['native', 'wasm-direct']
SAME = 'which prints the same at -O0, -O1 and -O2'


def stem(module):
    return module[len('test_'):] if module.startswith('test_') else module


def upstream_error(stderr):
    for line in stderr.splitlines():
        if ': error: ' in line:
            return line.split(': error: ', 1)[1].strip()
    return stderr.strip().splitlines()[0] if stderr.strip() else ''


def runtime_error(stderr):
    for line in stderr.splitlines():
        if line.startswith('goose runtime error: '):
            return re.sub(r' \([^()]*\)$', '', line[len('goose runtime error: '):]).strip()
    return None


def main():
    db = json.loads((HERE / 'db.json').read_text())
    decisions = json.loads((HERE / 'decisions.json').read_text())
    meta = json.loads((HERE / 'reasons.json').read_text())
    reasons, causes = meta['reasons'], meta['causes']
    rows, excluded, kept, gaps = [], [], [], []
    for e in sorted(db, key=lambda e: (stem(sorted(e['modules'])[0]), e['hash'])):
        h = e['hash']
        decision = decisions.get(h, {})
        modules = sorted(e['modules'])
        home = stem(modules[0])
        record = {'hash': h, 'sha256': e['sha256'], 'modules': ['tests/' + m + '.py' for m in modules]}
        u = e['upstream']
        reason = decision.get('exclude')
        if reason is None and e['fixture_duplicate']:
            reason = 'duplicate-fixture'
            record['duplicate_of'] = e['fixture_duplicate']
        if reason is None and e['externs'] and u['O0']['exit'] != 0:
            reason = 'host-import'
            record['externs'] = sorted(set(e['externs']))
        if reason is None and 'constant exceeds 32 bit' in u['O0']['stderr']:
            reason = 'upstream-toolchain'
        if reason is not None:
            if reason not in reasons:
                raise SystemExit('unknown reason ' + reason)
            record['reason'] = reason
            if u['check']['exit'] == 0 and u['O0']['exit'] in (0, 1) and reason not in ('host-import', 'upstream-toolchain'):
                record['upstream_stdout'] = u['O0']['stdout'][:300]
            for key in ('note', 'spec', 'ours'):
                if decision.get(key):
                    record[key] = decision[key]
            excluded.append(record)
            continue
        source = FIXTURES / home / (h + '.goose')
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(e['text'])
        relative = str(source.relative_to(ROOT))
        record['fixture'] = relative
        origin = ' and '.join('tests/' + m + '.py' for m in modules)
        captured = 'generated program captured from ' + origin + ', a C++-compiler-era test, by the upstream differential run'
        targets = decision.get('targets', TARGETS)
        levels = decision.get('levels', [0, 2])
        same = all(u['O%d' % l]['stdout'] == u['O0']['stdout'] and u['O%d' % l]['exit'] == u['O0']['exit'] for l in (1, 2))
        if not same:
            raise SystemExit(h + ': upstream levels differ; decide in decisions.json')
        if u['check']['exit'] != 0 or decision.get('false_accept'):
            if decision.get('false_accept'):
                provenance = 'Must be rejected: ' + decision['false_accept'] + '; ' + captured + '.'
            else:
                provenance = ('Must be rejected: plain upstream 32a4f44 (goose check) rejects it: "' +
                              upstream_error(u['check']['stderr']) + '"; ' + captured + '.')
            body = {'phase': 'type-error', 'expect': {'stderr_contains': decision['stderr_contains']}}
            record['phase'] = 'type-error'
        else:
            base = u['O0']
            expect = {'stdout': base['stdout'], 'exit': base['exit']}
            if base['exit'] != 0:
                expect['stderr_contains'] = decision.get('stderr_contains', [runtime_error(base['stderr'])])
            provenance = (captured[0].upper() + captured[1:] + '; expected output from plain upstream 32a4f44 '
                          '(goose run), ' + SAME + '.')
            if decision.get('note'):
                provenance += ' ' + decision['note']
            body = {'phase': 'run', 'stdin': '', 'expect': expect}
            record['phase'] = 'run'
        for target in targets:
            row = {'id': PREFIX + home + '/' + h + '/' + target, 'source': relative, 'phase': body['phase'],
                   'target': target, 'levels': levels}
            pages = decision.get('maximum_pages', {}).get(target)
            if pages is not None:
                row['maximum_pages'] = pages
            if 'stdin' in body:
                row['stdin'] = body['stdin']
            row['expect'] = dict(body['expect'])
            row['provenance'] = provenance
            rows.append(row)
        record['targets'] = targets
        record['levels'] = levels
        if decision.get('maximum_pages'):
            record['maximum_pages'] = decision['maximum_pages']
        if decision.get('gap'):
            if decision['gap'] not in causes:
                raise SystemExit('unknown cause ' + decision['gap'])
            record['gap'] = decision['gap']
            record['gap_targets'] = decision.get('gap_targets', targets)
            for target in record['gap_targets']:
                for level in levels:
                    gaps.append([PREFIX + home + '/' + h + '/' + target, level])
        if decision.get('note') and 'note' not in record:
            record['note'] = decision['note']
        kept.append(record)
    (HERE / 'rows.json').write_text(json.dumps({'rows': rows, 'gaps': gaps}, indent=1) + '\n')
    counts = {}
    for r in excluded:
        counts[r['reason']] = counts.get(r['reason'], 0) + 1
    manifest = {
        'schema': 'goose-harvest-manifest-v1',
        'description': 'Programs captured from the C++-compiler-era tests/test_*.py modules, which asserted the C++ '
                       "compiler's internals (its --offline option, --wasm-stats fields, goose.regions sections). "
                       'Their subprocess calls were recorded with assertions disabled, and each unique source was run '
                       'with plain upstream 32a4f44 (goose run and goose check, its own stdlib) at -O0, -O1 and -O2.',
        'upstream': {'revision': '32a4f44', 'spec': 'goose_spec.md at 2e2bede'},
        'counts': {'captured_files': sum(len(e['modules']) for e in db), 'unique_sources': len(db),
                   'duplicates_across_modules': sum(len(e['modules']) for e in db) - len(db),
                   'contracted': len(kept), 'excluded': len(excluded), 'excluded_by_reason': counts,
                   'rows': len(rows), 'known_gap_rows': len(gaps)},
        'reasons': {key: reasons[key] for key in sorted(counts)},
        'gap_causes': {key: causes[key] for key in sorted({r['gap'] for r in kept if r.get('gap')})},
        'excluded': excluded, 'contracted': kept}
    (HERE / 'manifest.json').write_text(json.dumps(manifest, indent=1) + '\n')
    print(len(db), 'unique;', len(kept), 'kept;', len(excluded), 'excluded', counts, ';', len(rows), 'rows;',
          len(gaps), 'gap rows')


if __name__ == '__main__':
    main()
