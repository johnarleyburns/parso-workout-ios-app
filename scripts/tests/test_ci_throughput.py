#!/usr/bin/env python3
"""Exercise CI drivers with fake tools; no Apple SDK or network needed."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def workflow(name):
    return json.loads(subprocess.check_output([
        'ruby', '-rjson', '-ryaml', '-e',
        'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))',
        str(ROOT / '.github/workflows' / name)], text=True))


class ThroughputTests(unittest.TestCase):
    def test_pr_jobs_overlap_but_required_gate_rejects_every_non_success(self):
        jobs = workflow('pr-validation.yml')['jobs']
        self.assertNotIn('needs', jobs['host-tests'])
        self.assertNotIn('needs', jobs['app-build'])
        gate = jobs['validate']
        self.assertEqual(set(gate['needs']), {'host-tests', 'app-build'})
        self.assertIn('always()', gate['if'])
        for a in ['success', 'failure', 'cancelled', 'skipped']:
            for b in ['success', 'failure', 'cancelled', 'skipped']:
                result = subprocess.run(['bash', '-c', gate['steps'][0]['run']],
                    env={**os.environ, 'HOST_TESTS': a, 'APP_BUILD': b}, capture_output=True)
                self.assertEqual(result.returncode == 0, a == b == 'success')

    def test_release_archives_in_parallel_but_upload_requires_both_jobs(self):
        jobs = workflow('ios.yml')['jobs']
        self.assertNotIn('needs', jobs['archive'])
        upload = jobs['testflight-build']
        self.assertEqual(set(upload['needs']), {'core-tests', 'archive'})
        self.assertNotIn('always()', upload.get('if', ''))
        self.assertNotIn('continue-on-error', upload)
        names = [step.get('name', '') for step in upload['steps']]
        self.assertLess(names.index('Restore signed archive'), names.index('Upload to TestFlight'))
        archive_steps = jobs['archive']['steps']
        self.assertFalse(any(step.get('name') == 'Upload to TestFlight' for step in archive_steps))
        self.assertTrue(any('tar -cf' in step.get('run', '') for step in archive_steps))
        self.assertEqual(set(jobs['deployment-report']['needs']), {'core-tests', 'archive', 'testflight-build'})

    def test_signed_archive_handoff_preserves_symlinks_and_execute_permissions(self):
        jobs = workflow('ios.yml')['jobs']
        pack = next(s['run'] for s in jobs['archive']['steps'] if s.get('name') == 'Package signed archive')
        restore = next(s['run'] for s in jobs['testflight-build']['steps'] if s.get('name') == 'Restore signed archive')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / 'build/Cadence.xcarchive/Products/Applications/Cadence.app'
            app.mkdir(parents=True)
            binary = app / 'Cadence'
            binary.write_bytes(b'fake signed executable')
            binary.chmod(0o755)
            (app / 'Current').symlink_to('Cadence')
            env = {**os.environ, 'RUNNER_TEMP': tmp}
            subprocess.run(['bash', '-ec', pack], env=env, cwd=root, check=True)
            (root / 'signed-archive').mkdir()
            (root / 'Cadence.xcarchive.tar').rename(root / 'signed-archive/Cadence.xcarchive.tar')
            destination = root / 'restored'
            destination.mkdir()
            subprocess.run(['bash', '-ec', restore], env=env, cwd=destination, check=True)
            restored = destination / 'build/Cadence.xcarchive/Products/Applications/Cadence.app'
            self.assertEqual((restored / 'Cadence').read_bytes(), binary.read_bytes())
            self.assertEqual((restored / 'Cadence').stat().st_mode & 0o777, 0o755)
            self.assertTrue((restored / 'Current').is_symlink())
            self.assertEqual(os.readlink(restored / 'Current'), 'Cadence')

    def test_test_driver_preserves_filters_and_propagates_failure(self):
        # Swift Testing schedules itself concurrently regardless of how swift
        # test is invoked, so ci-test.sh no longer picks a serial/parallel mode
        # (there is no XCTest content left for --parallel/--no-parallel to shard).
        with tempfile.TemporaryDirectory() as tmp:
            tool = Path(tmp) / 'swift'
            tool.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE"\nexit "${FAKE_EXIT:-0}"\n')
            tool.chmod(0o755)
            env = {**os.environ, 'PATH': tmp + ':' + os.environ['PATH'], 'CAPTURE': tmp + '/args'}
            driver = ['bash', str(ROOT / 'scripts/ci-test.sh'), '--filter', 'ProductionFlowHarnessTests']
            result = subprocess.run(driver, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            args = Path(env['CAPTURE']).read_text().splitlines()
            self.assertEqual(args, ['test', '--package-path', 'CadenceCore',
                                     '--filter', 'ProductionFlowHarnessTests'])
            self.assertEqual(subprocess.run(driver, env={**env, 'FAKE_EXIT': '17'},
                                            capture_output=True).returncode, 17)

    def test_validation_modes_do_not_repeat_harness_and_build_stays_release(self):
        source = (ROOT / 'scripts/ci-validate.sh').read_text()
        self.assertNotIn('bash scripts/run-verification-harness.sh', source)
        self.assertIn('--tests', source)
        self.assertIn('--build', source)
        self.assertIn('-configuration Release', source)
        self.assertIn('-showBuildTimingSummary', source)

    def test_validation_modes_execute_only_the_selected_work_and_propagate_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / 'scripts'
            scripts.mkdir()
            for name in ['ci-test', 'xcodebuild-safe', 'check-owned-warnings',
                         'test-check-owned-warnings', 'check-test-pyramid', 'check-no-network',
                         'check-history-safety', 'check-watch-appicon', 'check-watch-background-modes',
                         'check-xcodebuild-platform', 'check-ci-no-simulators', 'check-release-safety']:
                (scripts / (name + '.sh')).write_text(
                    '#!/bin/bash\nprintf "%s\\n" "' + name + ' $*" >> "$CAPTURE"\n'
                    'if [[ "${FAIL_STEP:-}" == "' + name + '" ]]; then exit 19; fi\n')
            env = {**os.environ, 'CI_VALIDATE_ROOT': tmp, 'RUNNER_TEMP': tmp, 'CAPTURE': tmp + '/calls'}
            command = ['bash', str(ROOT / 'scripts/ci-validate.sh')]
            result = subprocess.run(command + ['--tests'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = Path(env['CAPTURE']).read_text()
            self.assertIn('ci-test', calls)
            self.assertNotIn('xcodebuild-safe', calls)
            Path(env['CAPTURE']).unlink()
            result = subprocess.run(command + ['--build'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = Path(env['CAPTURE']).read_text()
            self.assertNotIn('ci-test', calls)
            self.assertIn('-configuration Release', calls)
            self.assertIn('-showBuildTimingSummary', calls)
            self.assertNotIn('run-verification-harness', calls)
            for mode, fail in [('--tests', 'ci-test'), ('--build', 'xcodebuild-safe'),
                               ('--build', 'check-owned-warnings')]:
                result = subprocess.run(command + [mode], env={**env, 'FAIL_STEP': fail}, capture_output=True)
                self.assertNotEqual(result.returncode, 0, (mode, fail))
            self.assertNotEqual(subprocess.run(command + ['--unknown'], env=env, capture_output=True).returncode, 0)

    def test_benchmark_compiles_once_and_reuses_the_identical_full_suite(self):
        with tempfile.TemporaryDirectory() as tmp:
            tool = Path(tmp) / 'swift'
            tool.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CAPTURE"\n')
            tool.chmod(0o755)
            env = {**os.environ, 'PATH': tmp + ':' + os.environ['PATH'],
                   'RUNNER_TEMP': tmp, 'CAPTURE': tmp + '/calls'}
            result = subprocess.run(['bash', str(ROOT / 'scripts/benchmark-host-tests.sh')],
                                    env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = Path(env['CAPTURE']).read_text().splitlines()
            self.assertEqual(sum(call.startswith('build ') for call in calls), 1)
            # Two full-suite timing runs plus the dedicated search-benchmark lane.
            self.assertEqual(sum(call.startswith('test ') for call in calls), 3)
            self.assertTrue(all('--skip-build' in call for call in calls if call.startswith('test ')))
            timing = (Path(tmp) / 'cadence-test-benchmark/timing-seconds.csv').read_text().splitlines()
            self.assertEqual([line.split(',')[0] for line in timing], ['run-1', 'run-2'])

    def test_cache_scopes_toolchains_dependencies_and_commits_are_isolated(self):
        cache = module('cache', ROOT / 'scripts/ci-cache-key.py')
        args = dict(scope='host', system='Darwin', arch='arm64', toolchain='Xcode 27\nSwift 6',
                    inputs=b'manifest-lock', sha='abc')
        baseline = cache.identity(**args)
        for key, value in [('scope', 'archive'), ('toolchain', 'Xcode 28'), ('inputs', b'new-lock'),
                           ('arch', 'x86_64')]:
            self.assertNotEqual(baseline['prefix'], cache.identity(**{**args, key: value})['prefix'])
        another = cache.identity(**{**args, 'sha': 'def'})
        self.assertEqual(baseline['prefix'], another['prefix'])
        self.assertNotEqual(baseline['key'], another['key'])
        action = (ROOT / '.github/actions/build-cache/action.yml').read_text()
        self.assertNotIn('build.keychain', action)
        self.assertNotIn('private_keys', action)
        self.assertNotIn('Library/Developer/Xcode/DerivedData/*', action)



if __name__ == '__main__':
    unittest.main()
