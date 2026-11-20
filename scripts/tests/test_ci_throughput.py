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
    def test_pull_request_jobs_overlap_but_the_required_gate_rejects_every_non_success(self):
        jobs = workflow('ios.yml')['jobs']
        self.assertNotIn('needs', jobs['host-tests'])
        self.assertNotIn('needs', jobs['app-build'])
        gate = jobs['validate']
        self.assertEqual(set(gate['needs']), {'host-tests', 'app-build'})
        self.assertIn('always()', gate['if'])
        self.assertIn("github.event_name == 'pull_request'", gate['if'])
        for a in ['success', 'failure', 'cancelled', 'skipped']:
            for b in ['success', 'failure', 'cancelled', 'skipped']:
                result = subprocess.run(['bash', '-c', gate['steps'][0]['run']],
                    env={**os.environ, 'HOST_TESTS': a, 'APP_BUILD': b}, capture_output=True)
                self.assertEqual(result.returncode == 0, a == b == 'success')

    def test_release_archives_in_parallel_but_upload_requires_both_jobs(self):
        jobs = workflow('ios.yml')['jobs']
        self.assertNotIn('needs', jobs['archive'])
        self.assertIn("github.ref == 'refs/heads/main'", jobs['archive']['if'])
        upload = jobs['testflight-build']
        self.assertEqual(set(upload['needs']), {'host-tests', 'archive'})
        condition = upload.get('if', '')
        self.assertIn("needs.host-tests.result == 'success'", condition)
        self.assertIn("needs.archive.result == 'success'", condition)
        self.assertNotIn('continue-on-error', upload)
        names = [step.get('name', '') for step in upload['steps']]
        self.assertLess(names.index('Restore signed archive'), names.index('Upload to TestFlight'))
        archive_steps = jobs['archive']['steps']
        self.assertFalse(any(step.get('name') == 'Upload to TestFlight' for step in archive_steps))
        self.assertTrue(any('tar -cf' in step.get('run', '') for step in archive_steps))
        self.assertEqual(set(jobs['deployment-report']['needs']), {'host-tests', 'archive', 'testflight-build'})

    def test_one_workflow_owns_pr_and_release_and_only_main_seeds_the_cache(self):
        jobs = workflow('ios.yml')['jobs']
        self.assertEqual(set(jobs), {'host-tests', 'app-build', 'validate', 'archive',
                                     'testflight-build', 'deployment-report'})
        triggers = workflow('ios.yml')['true']
        self.assertIn('pull_request', triggers)
        self.assertIn('push', triggers)
        seeds = [step for step in jobs['app-build']['steps']
                 if step.get('name') == 'iPhone and embedded Watch build with guardrails']
        self.assertEqual(len(seeds), 1)
        # main may skip the rebuild when the shared seed already exists.
        self.assertIn("steps.cache.outputs.matched-key == ''", seeds[0]['if'])
        cache = next(step for step in jobs['app-build']['steps'] if step.get('uses', '').endswith('build-cache'))
        self.assertIn("github.ref == 'refs/heads/main'", cache['with']['save'])

    def test_tree_attestation_skips_only_an_identical_tree_with_both_checks_green(self):
        script = ROOT / '.github/scripts/tree-validation-attestation.sh'
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            git = ['git', '-c', 'user.email=t@example.com', '-c', 'user.name=t']
            subprocess.run(['git', 'init', '-q'], cwd=root, check=True)
            (root / 'a').write_text('one')
            subprocess.run(git + ['add', 'a'], cwd=root, check=True)
            subprocess.run(git + ['commit', '-qm', 'one'], cwd=root, check=True)
            first = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            (root / 'a').write_text('two')
            subprocess.run(git + ['commit', '-qam', 'two'], cwd=root, check=True)
            second = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()

            fake = root / 'gh'
            fake.write_text('''#!/usr/bin/env bash
case "$*" in
  *"--jq"*) printf '7\n' ;;
  *"/pulls/7") printf '{"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"%s","head":{"sha":"%s"}}\n' "$SHA" "$PR_HEAD" ;;
  *"/check-runs"*) printf '%s\n' "${CHECKS:-}" ;;
  *) printf '{}\n' ;;
esac
''')
            fake.chmod(0o755)

            def run(sha, pr_head, checks, force='0'):
                env = {**os.environ, 'PATH': f'{root}:{os.environ["PATH"]}',
                       'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/heads/main',
                       'GITHUB_REPOSITORY': 'o/r', 'GITHUB_SHA': sha,
                       'FORCE_TESTS': force, 'SHA': sha, 'PR_HEAD': pr_head, 'CHECKS': checks}
                out = subprocess.run(['bash', str(script)], cwd=root, env=env,
                                     capture_output=True, text=True)
                self.assertEqual(out.returncode, 0, out.stderr)
                return out.stdout.strip()

            green = ('{"check_runs":[{"name":"host-tests","status":"completed","conclusion":"success"},'
                     '{"name":"app-build","status":"completed","conclusion":"success"}]}')
            red = ('{"check_runs":[{"name":"host-tests","status":"completed","conclusion":"success"},'
                   '{"name":"app-build","status":"completed","conclusion":"failure"}]}')
            self.assertEqual(run(second, second, green), 'skip=true')
            self.assertEqual(run(second, second, red), 'skip=false')
            self.assertEqual(run(second, first, green), 'skip=false')
            self.assertEqual(run(second, second, green, force='1'), 'skip=false')

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



    def test_pr_cache_pruning_deletes_only_closed_pull_request_entries(self):
        script = ROOT / '.github/scripts/prune-pr-caches.sh'
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / 'deleted'
            fake = root / 'gh'
            fake.write_text("""#!/usr/bin/env bash
case "$*" in
  *"/pulls/41"*) printf 'closed\n' ;;
  *"/pulls/42"*) printf 'open\n' ;;
  *"-X DELETE"*)
    printf '%s\n' "${@: -1}" >> "$DELETED" ;;
  *"--jq"*)
    printf '11\trefs/pull/41/merge\t100\n'
    printf '12\trefs/pull/42/merge\t100\n'
    printf '13\trefs/heads/main\t100\n' ;;
esac
""")
            fake.chmod(0o755)
            env = {**os.environ, 'PATH': f'{root}:{os.environ["PATH"]}',
                   'GITHUB_REPOSITORY': 'o/r', 'DELETED': str(log)}
            out = subprocess.run(['bash', str(script)], env=env,
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            deleted = log.read_text().split()
            self.assertEqual(deleted, ['repos/o/r/actions/caches/11'])


if __name__ == '__main__':
    unittest.main()
