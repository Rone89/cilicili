#!/usr/bin/env python3
"""Select an installed Xcode 26 toolchain and simulator on disposable CI hosts."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


MINIMUM_XCODE = (26, 5)
MINIMUM_IOS = (26, 1)


def parse_xcode_version(output: str) -> tuple[int, ...]:
    match = re.search(r"^Xcode\s+(\d+(?:\.\d+)*)\s*$", output, re.MULTILINE)
    if not match:
        raise ValueError("Could not parse xcodebuild -version output")
    return tuple(int(part) for part in match.group(1).split("."))


def supported_xcode(version: tuple[int, ...]) -> bool:
    return version[0] == 26 and version >= MINIMUM_XCODE


def select_simulator(payload: dict) -> tuple[str, str]:
    candidates = []
    for runtime, devices in payload.get("devices", {}).items():
        match = re.fullmatch(
            r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)",
            runtime,
        )
        if not match:
            continue
        version = tuple(int(part) for part in match.group(1).split("-"))
        if version[0] != 26 or version < MINIMUM_IOS:
            continue
        for device in devices:
            name = device.get("name", "")
            udid = device.get("udid", "")
            if not device.get("isAvailable", False) or not name.startswith("iPhone"):
                continue
            if not re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
                continue
            candidates.append((version, name == "iPhone 17", name, udid))
    if not candidates:
        raise RuntimeError(
            "No available iPhone simulator running iOS 26.1+ within iOS 26. "
            "Inspect the runner inventory; this helper never creates simulators."
        )
    version, _, name, udid = max(candidates)
    label = f"{name}, iOS {'.'.join(map(str, version))}"
    return f"platform=iOS Simulator,id={udid}", label


def capture(command: list[str], *, env: dict | None = None) -> str:
    # Capture all output before parsing: a short-lived pipe reader can make
    # xcodebuild -version throw NSFileHandleOperationException / Broken pipe.
    return subprocess.run(
        command, check=True, capture_output=True, text=True, env=env
    ).stdout.strip()


def append_environment(path_key: str, values: dict[str, str]) -> None:
    path = os.environ.get(path_key)
    if not path:
        raise RuntimeError(f"{path_key} is required")
    with open(path, "a", encoding="utf-8") as output:
        for key, value in values.items():
            if "\n" in value or "\r" in value:
                raise ValueError(f"Invalid multiline value for {key}")
            output.write(f"{key}={value}\n")


def select_xcode() -> None:
    paths = set(Path("/Applications").glob("Xcode*.app/Contents/Developer"))
    current = capture(["xcode-select", "-p"])
    if current:
        paths.add(Path(current))
    candidates = []
    for path in sorted(paths):
        if not path.is_dir():
            continue
        environment = dict(os.environ, DEVELOPER_DIR=str(path))
        try:
            output = capture(["xcodebuild", "-version"], env=environment)
            version = parse_xcode_version(output)
        except (subprocess.CalledProcessError, ValueError) as error:
            print(f"Skipping {path}: {error}", file=sys.stderr)
            continue
        print(f"Installed: {path}\n{output}", flush=True)
        if supported_xcode(version):
            candidates.append((version, str(path)))
    if not candidates:
        raise RuntimeError("Xcode 26.5 or a newer Xcode 26 release is required")
    version, path = max(candidates)
    append_environment("GITHUB_ENV", {
        "DEVELOPER_DIR": path,
        "XCODE_VERSION_MAJOR": str(version[0]),
    })
    print(f"Selected Xcode {'.'.join(map(str, version))}: {path}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["select-xcode", "select-simulator"])
    arguments = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true":
        parser.error("This helper is only for disposable GitHub Actions runners")
    try:
        if arguments.action == "select-xcode":
            select_xcode()
        else:
            inventory = capture(["xcrun", "simctl", "list", "devices", "available", "--json"])
            destination, label = select_simulator(json.loads(inventory))
            append_environment("GITHUB_OUTPUT", {"destination": destination})
            print(f"Selected existing simulator: {label}\n{destination}", flush=True)
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"ci-environment: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
