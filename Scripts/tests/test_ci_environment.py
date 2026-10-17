"""Regression tests for CI toolchain boundaries and simulator selection."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import os
import subprocess


SCRIPT = Path(__file__).resolve().parents[1] / "ci-environment.py"
SPEC = importlib.util.spec_from_file_location("ci_environment", SCRIPT)
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)


class CIEnvironmentTests(unittest.TestCase):
    def test_capture_drains_version_output_without_an_early_exit_pipe(self):
        output = "Xcode 26.5\nBuild version 17F2\n" + "diagnostic\n" * 20000
        completed = subprocess.CompletedProcess(["xcodebuild", "-version"], 0, output, "")
        with patch.object(ci.subprocess, "run", return_value=completed) as run:
            self.assertEqual(ci.capture(["xcodebuild", "-version"]), output.strip())
        self.assertTrue(run.call_args.kwargs["capture_output"])
        self.assertEqual(ci.parse_xcode_version(output), (26, 5))

    def test_only_supported_xcode_26_versions_are_accepted(self):
        self.assertFalse(ci.supported_xcode((26, 4, 1)))
        self.assertTrue(ci.supported_xcode((26, 5)))
        self.assertTrue(ci.supported_xcode((26, 6)))
        self.assertFalse(ci.supported_xcode((27, 0)))

    def test_version_parser_requires_an_xcode_version_line(self):
        with self.assertRaises(ValueError):
            ci.parse_xcode_version("Build version 17F2")
        self.assertEqual(ci.parse_xcode_version("Xcode 26.5.1\nBuild version 17F2"), (26, 5, 1))

    def test_selects_existing_ios_26_iphone_and_ignores_ios_27(self):
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                self.device("iPhone 18 Pro Max", "A")
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                self.device("iPad Pro", "B"),
                self.device("iPhone 17", "C"),
                self.device("iPhone 17 Pro", "D", available=False),
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
                self.device("iPhone 16 Pro", "E")
            ],
        }}
        destination, label = ci.select_simulator(payload)
        self.assertEqual(destination, "platform=iOS Simulator,id=" + "C" * 36)
        self.assertEqual(label, "iPhone 17, iOS 26.5")

    def test_rejects_inventory_without_a_compatible_existing_device(self):
        for runtime in ["iOS-26-0", "iOS-27-0", "tvOS-26-5"]:
            with self.subTest(runtime=runtime), self.assertRaises(RuntimeError):
                ci.select_simulator({"devices": {
                    "com.apple.CoreSimulator.SimRuntime." + runtime: [
                        self.device("iPhone 17", "A")
                    ]
                }})

    def test_rejects_unavailable_and_malformed_devices(self):
        with self.assertRaises(RuntimeError):
            ci.select_simulator({"devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    self.device("iPhone 17", "A", available=False),
                    {"name": "iPhone 17", "isAvailable": True, "udid": "not-a-uuid"},
                ]
            }})

    def test_writes_step_environment_with_real_newlines(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "env"
            with patch.dict(os.environ, {"GITHUB_ENV": str(path)}):
                ci.append_environment("GITHUB_ENV", {"DEVELOPER_DIR": "/Applications/Xcode 26.5.app/Contents/Developer"})
            self.assertEqual(
                path.read_text(),
                "DEVELOPER_DIR=/Applications/Xcode 26.5.app/Contents/Developer\n",
            )
            with patch.dict(os.environ, {"GITHUB_ENV": str(path)}):
                with self.assertRaises(ValueError):
                    ci.append_environment("GITHUB_ENV", {"DEVELOPER_DIR": "bad\nOTHER=value"})

    @staticmethod
    def device(name, character, available=True):
        return {"name": name, "udid": character * 36, "isAvailable": available}


if __name__ == "__main__":
    unittest.main()
