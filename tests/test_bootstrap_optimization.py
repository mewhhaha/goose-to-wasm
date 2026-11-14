#!/usr/bin/env python3
"""Bootstrap optimization must describe emitted C, including old seeds."""
import contextlib
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(relative):
    spec = importlib.util.spec_from_file_location('bootstrap_under_test', ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(data):
    return hashlib.sha256(data).hexdigest()


class BootstrapOptimizationTests(unittest.TestCase):
    def stage(self, seed_level, requested=None, verify=False, converge=False, seed_only=False,
              profile=None, version='clang version 21.1.0', fail_profile=False, changed=False, canonical_seed=False,
              jobs=None, cache=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'selfhost'; source.mkdir()
            (source / 'main.goose').write_text('fn main() {} // embed_file("../native/runtime.h")\n')
            native = root / 'native'; native.mkdir()
            (native / 'runtime.h').write_text('// pinned runtime asset\n')
            stdlib = root / 'stdlib'; stdlib.mkdir()
            (stdlib / 'base.goose').write_text('// library\n')
            seed = root / 'seed'; seed.mkdir()
            c = b'/* seed */\n'
            if canonical_seed:
                c = b'/* sources/main.goose stdlib */\n'
            compressed = gzip.compress(c, mtime=0)
            (seed / 'seed.c.gz').write_bytes(compressed)
            raw = io.BytesIO()
            with tarfile.open(fileobj=raw, mode='w') as archive:
                data = (stdlib / 'base.goose').read_bytes()
                info = tarfile.TarInfo('stdlib/base.goose'); info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
            bundle = gzip.compress(raw.getvalue(), mtime=0)
            (seed / 'sources.tar.gz').write_bytes(bundle)
            pin = dict(c_sha256=sha(c), compressed_sha256=sha(compressed),
                       source_bundle_sha256=sha(bundle),
                       source_sha256={'main.goose': sha((source / 'main.goose').read_bytes())},
                       asset_sha256={'native/runtime.h': sha((native / 'runtime.h').read_bytes())})
            if seed_level is not None:
                pin['goose_optimization'] = seed_level
            (seed / 'seed.json').write_text(json.dumps(pin))
            if changed:
                (source / 'main.goose').write_text('fn main() { changed() } // embed_file("../native/runtime.h")\n')
            emitted = b'/* sources/main.goose stdlib */\n'
            if profile is not None:
                data = b'profile data'
                (seed / 'profile.profdata').write_bytes(data)
                identity = dict(schema='goose-bootstrap-profile-v1', clang_major=21,
                                target='x86_64-unknown-linux-gnu',
                                base_flags=['-std=gnu11', '-O2', '-lm', '-ldl', '-pthread'],
                                c_basename='seed.c', c_sha256=sha(c), data_sha256=sha(data))
                if profile == 'emitted':
                    identity['c_sha256'] = sha(emitted)
                elif isinstance(profile, dict):
                    identity.update(profile)
                (seed / 'profile.json').write_text(json.dumps(identity))
                if profile == 'missing-data':
                    (seed / 'profile.profdata').unlink()
                if profile == 'invalid-json':
                    (seed / 'profile.json').write_text('broken')
                if profile == 'invalid-type':
                    (seed / 'profile.json').write_text('[]')
            cc = root / 'cc'; cc.write_bytes(b'fake C compiler\n'); cc.chmod(0o755)
            output = root / 'output'
            module = load('selfhost/bootstrap.py'); module.ROOT = root
            commands = []; emissions = []

            def run(argv, **kwargs):
                argv = list(map(str, argv)); commands.append(argv)
                if argv[0] == str(cc):
                    if argv[1:] == ['--version']:
                        return subprocess.CompletedProcess(argv, 0, version.encode(), b'')
                    if argv[1:] == ['-dumpmachine']:
                        return subprocess.CompletedProcess(argv, 0, b'x86_64-unknown-linux-gnu\n', b'')
                    if '-c' in argv or 'runtime.o' in argv:
                        # A unit build: objects, then the executable linked from them.
                        directory = Path(kwargs['cwd'])
                        self.assertTrue(directory.name.startswith('cc-build-'))
                        if '-c' in argv:
                            text = (directory / argv[argv.index('-c') + 1]).read_bytes()
                            (directory / argv[argv.index('-o') + 1]).write_bytes(text)
                        else:
                            (directory / argv[argv.index('-o') + 1]).write_bytes(b'plain:' + (directory / 'seed.c').read_bytes())
                        return subprocess.CompletedProcess(argv, 0, b'', b'')
                    self.assertEqual(argv[3], 'seed.c')
                    self.assertTrue(Path(kwargs['cwd']).name.startswith('cc-build-'))
                    staged = Path(kwargs['cwd']) / argv[3]
                    self.assertTrue(staged.is_file())
                    originals = {'cc-build-seed': 'seed.c', 'cc-build-goose': 'compiler.c',
                                 'cc-build-next-generation': 'next-generation.c'}
                    self.assertEqual(staged.read_bytes(), (output / originals[Path(kwargs['cwd']).name]).read_bytes())
                    profiled = any(arg.startswith('-fprofile-instr-use=') for arg in argv)
                    if profiled:
                        self.assertIn('-Werror=profile-instr-out-of-date', argv)
                        self.assertIn('-Werror=profile-instr-unprofiled', argv)
                        self.assertIn('-Werror=profile-instr-missing', argv)
                        if fail_profile:
                            return subprocess.CompletedProcess(argv, 1, b'', b'profile mismatch')
                    binary = b'plain:' + staged.read_bytes()
                    if profiled:
                        binary = b'profile:' + staged.read_bytes()
                    Path(argv[argv.index('-o') + 1]).write_bytes(binary)
                else:
                    emissions.append(argv)
                    self.assertEqual(argv[1], 'sources/main.goose')
                    self.assertEqual(argv[argv.index('--stdlib') + 1], 'stdlib')
                    self.assertEqual(Path(kwargs['cwd']), output)
                    self.assertEqual((Path(kwargs['cwd']) / argv[1]).read_bytes(),
                                     (source / 'main.goose').read_bytes())
                    self.assertEqual((Path(kwargs['cwd']) / 'native/runtime.h').read_bytes(),
                                     (native / 'runtime.h').read_bytes())
                    self.assertTrue((Path(kwargs['cwd']) / 'stdlib/base.goose').is_file())
                    data = ('/* ' + argv[1] + ' ' + argv[argv.index('--stdlib') + 1] + ' */\n').encode()
                    if jobs:
                        data += b'#ifdef G_RUNTIME_UNIT\n#else /* program units */\n#if G_IN_UNIT(  0)\n#endif\n#endif\n'
                    if converge and len(emissions) == 1:
                        data = b'/* first generation */\n'
                    Path(argv[argv.index('-o') + 1]).write_bytes(data)
                return subprocess.CompletedProcess(argv, 0, b'', b'')

            args = ['bootstrap', '--source-dir', str(source), '--seed-dir', str(seed),
                    '--stdlib', str(stdlib), '--native-dir', str(root / 'native'),
                    '--output-dir', str(output), '--cc', str(cc)]
            if requested is not None:
                args += ['--optimization', str(requested)]
            if verify:
                args += ['--verify']
            if seed_only:
                args += ['--seed-only']
            if jobs:
                args += ['--jobs', str(jobs)]
            if cache:
                args += ['--cache-dir', str(cache)]
            self.compiles = commands
            with patch.object(sys, 'argv', args), patch.object(module.subprocess, 'run', run), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(module.main(), 0)
            report = json.loads((output / 'report.json').read_text())
            self.assertEqual(report['status'], 'passed')
            self.assertEqual(report['input_sha256'], report['input_sha256_after'])
            for command in commands:
                if command[0] == str(cc) and command[1:] not in (['--version'], ['-dumpmachine']):
                    self.assertIn('-O2', command)
            actual = report['executable_build']
            prefix = b'plain:'
            if actual['profile_used']:
                prefix = b'profile:'
            self.assertEqual((output / 'goose').read_bytes()[:len(prefix)], prefix)
            self.assertEqual(report['profile_used'], actual['profile_used'])
            self.assertEqual(report['executable_c_sha256'], actual['c_sha256'])
            self.assertEqual(report['goose_optimization'], actual['goose_optimization'])
            return report, emissions

    def test_zero_seed_requested_two_reemits_and_verifies_every_generation(self):
        report, commands = self.stage(0, verify=True, converge=True)
        self.assertFalse(report.get('seed_matches_sources', False))
        self.assertEqual(report['goose_optimization'], 2)
        self.assertTrue(report['fixed_point'])
        self.assertEqual(len(commands), 3)
        for command in commands:
            self.assertIn('-O2', command)
            self.assertNotIn('-O0', command)

    def test_jobs_split_only_marked_c_without_profile(self):
        report, _ = self.stage(0, verify=True, converge=True, profile='emitted', jobs=3)
        # The seed's and first generation's C carry no unit marks and compile whole.
        self.assertNotIn('units', report['builds']['build-seed'])
        self.assertNotIn('units', report['builds']['build-goose'])
        split = report['builds']['build-next-generation']
        self.assertEqual(split['units'], 3)
        self.assertFalse(split['profile_used'])
        self.assertEqual(report['executable_build'], split)
        names = [row['name'] for row in report['commands']]
        for name in ('build-next-generation-runtime', 'build-next-generation-unit0', 'build-next-generation-unit2'):
            self.assertIn(name, names)
        self.assertEqual(names.index('build-next-generation'), max(names.index(name) for name in names if name.startswith('build-next-generation')))
        units = [row['command'] for row in report['commands'] if row['name'].startswith('build-next-generation-unit')]
        self.assertEqual(sorted(command[command.index('-c') - 1] for command in units), ['-DG_UNIT=0', '-DG_UNIT=1', '-DG_UNIT=2'])
        self.assertTrue(all('-DG_UNITS=3' in command for command in units))

    def test_cache_dir_reuses_identical_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / 'cache'
            first, _ = self.stage(0, verify=True, converge=True, profile={}, cache=cache)
            compiled = [command for command in self.compiles if '-o' in command]
            second, _ = self.stage(0, verify=True, converge=True, profile={}, cache=cache)
            builds = ('build-seed', 'build-goose', 'build-next-generation')
            self.assertEqual([first['builds'][name]['cache']['hit'] for name in builds], [False] * 3)
            self.assertEqual([second['builds'][name]['cache']['hit'] for name in builds], [True] * 3)
            # The seed keeps its profile when reused; nothing is compiled again.
            self.assertTrue(second['builds']['build-seed']['profile_used'])
            self.assertTrue(any(command[0].endswith('/cc') for command in compiled))
            self.assertFalse([command for command in self.compiles if command[0].endswith('/cc') and '-o' in command])
            self.assertEqual(first['executable_sha256'], second['executable_sha256'])

    def test_matching_optimized_seed_reuses_c(self):
        report, commands = self.stage(2)
        self.assertTrue(report['seed_matches_sources'])
        self.assertEqual(report['goose_optimization'], 2)
        self.assertEqual(commands, [])

    def test_old_seed_missing_level_is_zero(self):
        for seed_level in (None, 0):
            with self.subTest(seed_level=seed_level):
                report, commands = self.stage(seed_level, requested=0)
                self.assertTrue(report['seed_matches_sources'])
                self.assertEqual(report['goose_optimization'], 0)
                self.assertEqual(commands, [])
        report, commands = self.stage(None)
        self.assertEqual(report['goose_optimization'], 2)
        self.assertEqual(len(commands), 1)
        self.assertFalse(report.get('seed_matches_sources', False))

    def test_level_one_is_forwarded(self):
        report, commands = self.stage(0, requested=1, verify=True)
        self.assertEqual(report['goose_optimization'], 1)
        self.assertEqual(len(commands), 2)
        self.assertTrue(all('-O1' in command for command in commands))

    def test_seed_only_reports_actual_seed_level(self):
        for seed_level, expected in [(None, 0), (2, 2)]:
            with self.subTest(seed_level=seed_level):
                report, commands = self.stage(seed_level, seed_only=True)
                self.assertEqual(report['goose_optimization'], expected)
                self.assertEqual(report['requested_goose_optimization'], 2)
                self.assertEqual(commands, [])

    def test_emission_identity_is_independent_of_output_root(self):
        first, _ = self.stage(0)
        second, _ = self.stage(0)
        self.assertEqual(first['generated_c_sha256'], second['generated_c_sha256'])
        self.assertEqual(first['executable_sha256'], second['executable_sha256'])
        for command in first['commands']:
            if command['name'].startswith('build-'):
                self.assertEqual(command['command'][3], 'seed.c')

    def test_promoted_unprofiled_stage_does_not_inherit_seed_profile(self):
        report, _ = self.stage(2, profile={}, verify=True)
        # This mock's seed C differs from its compiler's fixed point, so verify
        # correctly promotes the unprofiled following C instead of inheriting PGO.
        self.assertFalse(report['profile_used'])
        self.assertTrue(report['builds']['build-seed']['profile_used'])
        self.assertEqual(report['executable_build'], report['builds']['build-next-generation'])

    def test_matching_profile_survives_verify_without_promotion(self):
        report, _ = self.stage(2, profile={}, verify=True, canonical_seed=True)
        self.assertTrue(report['profile_used'])
        self.assertEqual(report['executable_build'], report['builds']['build-seed'])
        self.assertEqual(len(report['builds']), 1)
        self.assertTrue(report['fixed_point'])

    def test_invalid_or_missing_sidecars_fall_back(self):
        for profile, reason in [('missing-data', 'data absent'),
                                ('invalid-json', 'invalid profile metadata'),
                                ('invalid-type', 'invalid profile metadata')]:
            with self.subTest(profile=profile):
                report, _ = self.stage(2, profile=profile, seed_only=True)
                self.assertFalse(report['profile_used'])
                self.assertIn(reason, report['executable_build']['profile_reason'])

    def test_promoted_stage_can_select_its_own_exact_profile(self):
        report, _ = self.stage(0, profile='emitted', verify=True, converge=True)
        self.assertTrue(report['profile_used'])
        self.assertFalse(report['builds']['build-seed']['profile_used'])
        self.assertFalse(report['builds']['build-goose']['profile_used'])
        self.assertTrue(report['builds']['build-next-generation']['profile_used'])
        self.assertEqual(report['executable_build'], report['builds']['build-next-generation'])

    def test_matching_seed_only_uses_profile(self):
        report, _ = self.stage(2, profile={}, seed_only=True)
        self.assertTrue(report['profile_used'])
        self.assertEqual(report['executable_build'], report['builds']['build-seed'])
        self.assertTrue(any(path.endswith('profile.json') for path in report['input_sha256']))
        self.assertTrue(any(path.endswith('profile.profdata') for path in report['input_sha256']))

    def test_changed_source_does_not_inherit_seed_profile(self):
        report, _ = self.stage(2, profile={}, changed=True)
        self.assertFalse(report['profile_used'])
        self.assertTrue(report['builds']['build-seed']['profile_used'])
        self.assertIn('c_sha256', report['executable_build']['profile_reason'])

    def test_profile_identity_and_integrity_fail_closed(self):
        for fields, reason in [({'clang_major': 20}, 'clang_major'),
                               ({'target': 'other'}, 'target'),
                               ({'base_flags': ['-O3']}, 'base_flags'),
                               ({'c_basename': 'compiler.c'}, 'c_basename'),
                               ({'c_sha256': 'wrong'}, 'c_sha256'),
                               ({'schema': 'wrong'}, 'schema'),
                               ({'data_sha256': 'wrong'}, 'checksum')]:
            with self.subTest(fields=fields):
                report, _ = self.stage(2, profile=fields, seed_only=True)
                self.assertFalse(report['profile_used'])
                self.assertIn(reason, report['executable_build']['profile_reason'])

    def test_non_clang_and_absent_profile_have_explicit_reasons(self):
        report, _ = self.stage(2, profile={}, version='gcc version 15', seed_only=True)
        self.assertFalse(report['profile_used'])
        self.assertIn('not Clang', report['executable_build']['profile_reason'])
        report, _ = self.stage(2, seed_only=True)
        self.assertIn('absent', report['executable_build']['profile_reason'])

    def test_profile_compile_failure_falls_back_with_failed_command(self):
        report, _ = self.stage(2, profile={}, seed_only=True, fail_profile=True)
        self.assertFalse(report['profile_used'])
        actual = report['executable_build']
        self.assertIn('failed', actual['profile_reason'])
        self.assertEqual(actual['profile_failed_command']['exit_code'], 1)
        self.assertEqual([row['name'] for row in report['commands']][-2:],
                         ['build-seed-profile', 'build-seed'])

    def test_installer_forwards_level_and_records_actual_report(self):
        for requested, report_level in [(None, 2), (0, 0), (1, 1), (None, None)]:
            with self.subTest(requested=requested, report_level=report_level), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); library = root / 'stdlib'; library.mkdir()
                (library / 'base.goose').write_text('// stdlib\n')
                build = root / 'build'; module = load('scripts/bootstrap.py'); module.ROOT = root
                captured = []

                def run(argv, **kwargs):
                    captured.append(argv)
                    stage = Path(argv[argv.index('--output-dir') + 1]); stage.mkdir(parents=True)
                    (stage / 'goose').write_bytes(b'fake executable\n')
                    report = dict(executable_sha256=sha(b'fake executable\n'), source_sha256={},
                                  stdlib_sha256={}, asset_sha256={}, cc='fake cc', cc_sha256='cc hash', seed_c_sha256='seed hash')
                    report.update(profile_used=True, executable_c_sha256='actual C',
                                  executable_build={'profile_used': True, 'profile_sha256': 'actual profile'})
                    if report_level is not None:
                        report['goose_optimization'] = report_level
                    (stage / 'report.json').write_text(json.dumps(report))
                    return subprocess.CompletedProcess(argv, 0)

                args = ['bootstrap', '--build-dir', str(build)]
                if requested is not None:
                    args += ['--optimization', str(requested)]
                with patch.object(sys, 'argv', args), patch.object(module.subprocess, 'run', run), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(module.main(), 0)
                expected = requested
                if expected is None:
                    expected = 2
                self.assertEqual(captured[0][captured[0].index('--optimization') + 1], str(expected))
                expected_metadata = report_level
                if expected_metadata is None:
                    expected_metadata = 0
                metadata = json.loads((build / 'toolchain.json').read_text())
                self.assertEqual(metadata['goose_optimization'], expected_metadata)
                self.assertTrue(metadata['profile_used'])
                self.assertEqual(metadata['executable_c_sha256'], 'actual C')
                self.assertEqual(metadata['executable_build']['profile_sha256'], 'actual profile')
                self.assertTrue((build / 'bin/goose').is_file())
                self.assertTrue((build / 'bin/stdlib/base.goose').is_file())


if __name__ == '__main__':
    unittest.main()
