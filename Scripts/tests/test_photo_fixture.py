"""Exercise the actual preflight shell with fake Xcode/simctl processes."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
SIMULATOR = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


class PhotoFixtureTests(unittest.TestCase):
    def run_preflight(self, status, log):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / "bin"
            commands.mkdir()
            python = commands / "python3"
            python.write_text(f"#!{sys.executable}\n" + textwrap.dedent("""\
                import json, os, pathlib, sys, time
                root = pathlib.Path(os.environ['RUNNER_TEMP'])
                if sys.argv[1] == 'Scripts/build-cache.py':
                    (root / 'xcode-args.json').write_text(json.dumps(sys.argv[2:]))
                    # Let the real background importer observe the fake device.
                    deadline = time.monotonic() + 5
                    while not (root / 'imported').exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    print(os.environ['FAKE_PREFLIGHT_LOG'])
                    sys.exit(int(os.environ['FAKE_PREFLIGHT_STATUS']))
                os.execv(sys.executable, [sys.executable] + sys.argv[1:])
                """))
            simctl = commands / "xcrun"
            simctl.write_text(f"#!{sys.executable}\n" + textwrap.dedent("""\
                import json, os, pathlib, sys
                root = pathlib.Path(os.environ['RUNNER_TEMP'])
                with (root / 'simctl-calls').open('a') as trace:
                    trace.write(json.dumps(sys.argv[1:]) + '\\n')
                if sys.argv[1:4] == ['simctl', 'list', 'devices']:
                    print(json.dumps({'devices': {'runtime': [{
                        'udid': os.environ['FAKE_SIMULATOR'], 'state': 'Booted'
                    }]}}))
                elif sys.argv[1:3] == ['simctl', 'addmedia']:
                    assert sys.argv[3] == os.environ['FAKE_SIMULATOR']
                    assert pathlib.Path(sys.argv[4]).read_bytes().startswith(b'\\x89PNG')
                    (root / 'imported').touch()
                else:
                    sys.exit(9)
                """))
            python.chmod(0o755)
            simctl.chmod(0o755)
            output = root / "output"
            output.touch()
            result = subprocess.run(
                ["bash", "Scripts/prepare-ui-photo-fixture.sh"], cwd=ROOT,
                env=dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                         RUNNER_TEMP=directory, GITHUB_OUTPUT=str(output), UI_SHARD="1",
                         PROJECT="bili.xcodeproj", SCHEME="bili",
                         TEST_DESTINATION="platform=iOS Simulator,id=" + SIMULATOR,
                         FAKE_SIMULATOR=SIMULATOR, FAKE_PREFLIGHT_STATUS=str(status),
                         FAKE_PREFLIGHT_LOG=log),
                capture_output=True, text=True, timeout=15,
            )
            args = json.loads((root / "xcode-args.json").read_text())
            self.assertIn("-retry-tests-on-failure", args)
            self.assertEqual(args[args.index("-test-iterations") + 1], "2")
            self.assertTrue((root / "imported").exists())
            calls = [json.loads(line) for line in (root / "simctl-calls").read_text().splitlines()]
            self.assertTrue(all(call[1] in ("list", "addmedia") for call in calls))
            return result, output.read_text(), (root / "photo-preflight.log").read_text()

    def test_success_requires_media_import_and_does_not_report_a_retry(self):
        result, output, _ = self.run_preflight(0, "** TEST SUCCEEDED **")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "")

    def test_recovered_launch_retains_first_failure_for_artifact_upload(self):
        log = "Test Case '-[Preflight testLaunch]' failed (1.0 seconds).\n** TEST SUCCEEDED **"
        result, output, retained = self.run_preflight(0, log)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "had_test_failures=true\n")
        self.assertIn("failed (1.0 seconds)", retained)

    def test_two_failed_attempts_preserve_xcode_exit_status(self):
        result, output, _ = self.run_preflight(
            65, "Test Case '-[Preflight testLaunch]' failed (1.0 seconds).\n** TEST FAILED **")
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertEqual(output, "had_test_failures=true\n")
