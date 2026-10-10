#!/usr/bin/env python3
"""Manage cilicili's shared and temporary Xcode DerivedData directories."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parent.parent
BUILD_ROOT = ROOT / "build"
SHARED_ROOT = BUILD_ROOT / "DerivedData"
TEMP_ROOT = BUILD_ROOT / "Temp" / "DerivedData"
LOCK_ROOT = BUILD_ROOT / "Temp" / ".build-cache-locks"
MARKER = ".cilicili-temporary-derived-data.json"
RETENTION = dt.timedelta(days=7)
LABEL_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$")


def now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def timestamp(value: dt.datetime) -> str:
    return value.isoformat(timespec="seconds")


def parse_timestamp(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def xcode_major() -> str:
    try:
        result = subprocess.run(
            ["xcodebuild", "-version"], check=True, capture_output=True, text=True
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError(f"Unable to read the selected Xcode version: {error}") from error

    match = re.search(r"^Xcode\s+(\d+)(?:\.|\s|$)", result.stdout, re.MULTILINE)
    if not match:
        raise RuntimeError(f"Could not parse the selected Xcode version: {result.stdout.strip()}")
    return match.group(1)


def shared_path() -> Path:
    return SHARED_ROOT / f"Xcode-{xcode_major()}"


def ensure_directory(path: Path, *, create: bool) -> Path | None:
    if path.is_symlink():
        raise RuntimeError(f"Refusing symlinked build-cache directory: {path}")
    if not path.exists():
        if not create:
            return None
        path.mkdir()
    if not path.is_dir():
        raise RuntimeError(f"Build-cache path is not a directory: {path}")
    resolved = path.resolve(strict=True)
    if resolved != path:
        raise RuntimeError(f"Build-cache directory resolves outside its expected path: {path}")
    return resolved


def ensure_temp_root(*, create: bool) -> Path | None:
    if ensure_directory(BUILD_ROOT, create=create) is None:
        return None
    if ensure_directory(BUILD_ROOT / "Temp", create=create) is None:
        return None
    return ensure_directory(TEMP_ROOT, create=create)


def ensure_shared_cache(path: Path, *, create: bool) -> Path | None:
    if ensure_directory(BUILD_ROOT, create=create) is None:
        return None
    if ensure_directory(SHARED_ROOT, create=create) is None:
        return None
    return ensure_directory(path, create=create)


def ensure_shared_cache_root(*, create: bool) -> Path | None:
    if ensure_directory(BUILD_ROOT, create=create) is None:
        return None
    return ensure_directory(SHARED_ROOT, create=create)


def ensure_lock_root() -> Path:
    if ensure_directory(BUILD_ROOT, create=True) is None:
        raise RuntimeError(f"Could not prepare build directory: {BUILD_ROOT}")
    if ensure_directory(BUILD_ROOT / "Temp", create=True) is None:
        raise RuntimeError(f"Could not prepare temporary directory: {BUILD_ROOT / 'Temp'}")
    if ensure_directory(LOCK_ROOT, create=True) is None:
        raise RuntimeError(f"Could not prepare build-cache lock directory: {LOCK_ROOT}")
    return LOCK_ROOT


def lock_path(cache_path: Path) -> Path:
    digest = hashlib.sha256(str(cache_path.resolve()).encode()).hexdigest()[:24]
    return LOCK_ROOT / f"{digest}.lock"


class CacheLock:
    def __init__(self, cache_path: Path, *, nonblocking: bool = False):
        self.path = lock_path(cache_path)
        self.nonblocking = nonblocking
        self.fd: int | None = None

    def __enter__(self) -> "CacheLock":
        ensure_lock_root()
        if self.path.is_symlink():
            raise RuntimeError(f"Refusing symlinked build-cache lock: {self.path}")
        no_follow = getattr(os, "O_NOFOLLOW", 0)
        self.fd = os.open(self.path, os.O_CREAT | os.O_RDWR | no_follow, 0o600)
        flags = fcntl.LOCK_EX | (fcntl.LOCK_NB if self.nonblocking else 0)
        try:
            fcntl.flock(self.fd, flags)
        except BlockingIOError:
            os.close(self.fd)
            self.fd = None
            raise
        return self

    def __exit__(self, *_: object) -> None:
        if self.fd is not None:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            os.close(self.fd)
            self.fd = None


def write_marker(path: Path, metadata: dict[str, object]) -> None:
    marker_path = path / MARKER
    temporary_path = path / f"{MARKER}.new"
    temporary_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    temporary_path.replace(marker_path)


def read_marker(path: Path) -> dict[str, object] | None:
    try:
        metadata = json.loads((path / MARKER).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(metadata, dict):
        return None
    if metadata.get("schema") != 1 or metadata.get("project_root") != str(ROOT):
        return None
    try:
        recorded_path = Path(str(metadata["derived_data_path"])).resolve(strict=True)
        expected_root = ensure_temp_root(create=False)
    except (KeyError, OSError, RuntimeError):
        return None
    if expected_root is None or recorded_path != path.resolve(strict=True) or recorded_path.parent != expected_root:
        return None
    return metadata


def temporary_path(label: str, major: str) -> Path:
    if not LABEL_PATTERN.fullmatch(label):
        raise ValueError("Temporary cache labels must use 1-40 letters, numbers, dots, underscores or hyphens.")
    temp_root = ensure_temp_root(create=True)
    if temp_root is None:
        raise RuntimeError(f"Could not prepare temporary DerivedData root: {TEMP_ROOT}")
    created = now()
    name = (
        f"cilicili-{label}-Xcode-{major}-{created.strftime('%Y%m%dT%H%M%SZ')}"
        f"-{os.getpid()}-{uuid.uuid4().hex[:8]}"
    )
    path = temp_root / name
    path.mkdir(mode=0o700)
    resolved_root = temp_root
    if path.resolve(strict=True).parent != resolved_root:
        raise RuntimeError(f"Refusing temporary cache outside {resolved_root}: {path}")
    write_marker(
        path,
        {
            "schema": 1,
            "project_root": str(ROOT),
            "derived_data_path": str(path.resolve()),
            "label": label,
            "xcode_major": major,
            "state": "running",
            "created_at": timestamp(created),
            "started_at": timestamp(created),
        },
    )
    return path


def command_with_derived_data(command: list[str], cache_path: Path) -> list[str]:
    if not command or Path(command[0]).name != "xcodebuild":
        return command
    result: list[str] = []
    index = 0
    while index < len(command):
        if command[index] == "-derivedDataPath":
            index += 2
            continue
        result.append(command[index])
        index += 1
    result.extend(["-derivedDataPath", str(cache_path)])
    return result


def run_command(command: list[str], label: str | None) -> int:
    if not command:
        raise ValueError("Provide a command after '--'.")

    major = xcode_major()
    if label:
        cache_path = temporary_path(label, major)
    else:
        cache_path = ensure_shared_cache(SHARED_ROOT / f"Xcode-{major}", create=True)
        if cache_path is None:
            raise RuntimeError(f"Could not prepare shared DerivedData: {SHARED_ROOT}")
    if label:
        # temporary_path already created the leaf directory and its marker.
        assert cache_path.is_dir()

    environment = os.environ.copy()
    environment["CILICILI_DERIVED_DATA_PATH"] = str(cache_path)
    environment["CILICILI_CACHE_LOCK_HELD"] = str(cache_path)
    command = command_with_derived_data(command, cache_path)

    try:
        with CacheLock(cache_path):
            result = subprocess.run(command, cwd=ROOT, env=environment)
    except KeyboardInterrupt:
        if label:
            metadata = read_marker(cache_path) or {}
            metadata.update({"state": "failed", "failed_at": timestamp(now()), "exit_status": 130})
            write_marker(cache_path, metadata)
            print(f"Temporary cache retained for diagnosis: {cache_path}", file=sys.stderr)
        return 130
    except OSError as error:
        if label:
            metadata = read_marker(cache_path) or {}
            metadata.update({"state": "failed", "failed_at": timestamp(now()), "error": str(error)})
            write_marker(cache_path, metadata)
        raise RuntimeError(f"Could not start build command: {error}") from error

    if label:
        metadata = read_marker(cache_path) or {}
        if result.returncode == 0:
            metadata.update({"state": "completed", "completed_at": timestamp(now())})
            write_marker(cache_path, metadata)
            with CacheLock(cache_path):
                safe_remove_temporary_cache(cache_path, metadata)
            print(f"Removed successful temporary cache: {cache_path}")
        else:
            metadata.update(
                {"state": "failed", "failed_at": timestamp(now()), "exit_status": result.returncode}
            )
            write_marker(cache_path, metadata)
            expires = now() + RETENTION
            print(
                f"Build failed; temporary cache retained until at least {timestamp(expires)}: {cache_path}",
                file=sys.stderr,
            )
    if result.returncode == 0:
        # Run age-based cleanup once at task completion, never in a background job.
        clean(execute=True, quiet=True)
    return result.returncode


def safe_remove_temporary_cache(path: Path, metadata: dict[str, object]) -> None:
    """Remove one validated, marked immediate child of build/Temp/DerivedData."""
    try:
        expected_root = ensure_temp_root(create=False)
        if expected_root is None:
            raise RuntimeError("temporary cache root is missing")
        if path.is_symlink() or not path.is_dir():
            raise RuntimeError("cache is not a real directory")
        resolved = path.resolve(strict=True)
        if resolved.parent != expected_root or metadata.get("project_root") != str(ROOT):
            raise RuntimeError("cache path is outside the approved temporary cache root")
        if metadata.get("derived_data_path") != str(resolved):
            raise RuntimeError("cache marker does not match the directory")
        if not shutil.rmtree.avoids_symlink_attacks:
            raise RuntimeError("this Python does not provide symlink-safe recursive removal")
    except (OSError, RuntimeError) as error:
        raise RuntimeError(f"Refusing to remove temporary cache {path}: {error}") from error
    shutil.rmtree(resolved)


def directory_size(path: Path) -> int:
    total = 0
    for current, directories, files in os.walk(path, followlinks=False):
        directories[:] = [name for name in directories if not (Path(current) / name).is_symlink()]
        for name in files:
            try:
                total += (Path(current) / name).lstat().st_size
            except OSError:
                pass
    return total


def human_size(size: int) -> str:
    amount = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if amount < 1024 or unit == "TiB":
            return f"{amount:.1f} {unit}"
        amount /= 1024
    return f"{amount:.1f} TiB"


def temporary_candidates() -> list[tuple[Path, dict[str, object]]]:
    temp_root = ensure_temp_root(create=False)
    if temp_root is None:
        return []
    candidates: list[tuple[Path, dict[str, object]]] = []
    expected_root = temp_root
    for path in sorted(temp_root.iterdir()):
        if path.is_symlink() or not path.is_dir() or not path.name.startswith("cilicili-"):
            continue
        try:
            if path.resolve(strict=True).parent != expected_root:
                continue
        except (OSError, RuntimeError):
            continue
        metadata = read_marker(path)
        if metadata is not None:
            candidates.append((path, metadata))
    return candidates


def status() -> int:
    stable = shared_path()
    print(f"Shared DerivedData: {stable}")
    current_cache = ensure_shared_cache(stable, create=False)
    print(f"  {human_size(directory_size(current_cache)) if current_cache else 'not created'}")
    shared_root = ensure_shared_cache_root(create=False)
    if shared_root is not None:
        total = 0
        for path in sorted(shared_root.iterdir()):
            if path.is_symlink() or not path.is_dir() or not re.fullmatch(r"Xcode-\d+", path.name):
                continue
            size = directory_size(path)
            total += size
            if path != current_cache:
                print(f"  {path.name}: {human_size(size)}")
        print(f"Shared total: {human_size(total)}")
    print(f"Temporary root: {TEMP_ROOT}")
    candidates = temporary_candidates()
    if not candidates:
        print("  no managed temporary caches")
        return 0
    total = 0
    for path, metadata in candidates:
        size = directory_size(path)
        total += size
        print(f"  {metadata.get('state', 'unknown'):9} {human_size(size):>10}  {path.name}")
    print(f"Temporary total: {human_size(total)}")
    return 0


def clean(execute: bool, *, quiet: bool = False) -> int:
    cutoff = now() - RETENTION
    action = "DELETE" if execute else "DRY-RUN"
    if not quiet:
        print(f"{action}: managed temporary DerivedData older than 7 days (cutoff {timestamp(cutoff)})")
    eligible = 0
    total_bytes = 0
    for path, metadata in temporary_candidates():
        age_value = metadata.get("failed_at") or metadata.get("completed_at") or metadata.get("started_at") or metadata.get("created_at")
        try:
            age = parse_timestamp(str(age_value))
        except (TypeError, ValueError):
            if not quiet:
                print(f"SKIP invalid timestamp: {path}")
            continue
        if age > cutoff:
            if not quiet:
                print(f"KEEP younger than 7 days: {path} ({human_size(directory_size(path))})")
            continue

        try:
            with CacheLock(path, nonblocking=True):
                current = read_marker(path)
                if current is None:
                    if not quiet:
                        print(f"SKIP invalid marker: {path}")
                    continue
                if not execute:
                    size = directory_size(path)
                    eligible += 1
                    total_bytes += size
                    if not quiet:
                        print(f"WOULD DELETE: {path} ({human_size(size)})")
                    continue
                size = directory_size(path)
                safe_remove_temporary_cache(path, current)
                eligible += 1
                total_bytes += size
                if not quiet:
                    print(f"DELETED: {path} ({human_size(size)})")
        except BlockingIOError:
            if not quiet:
                print(f"KEEP in use: {path}")
        except (OSError, RuntimeError) as error:
            if not quiet:
                print(f"SKIP unsafe cache {path}: {error}")

    if not quiet and not execute and eligible == 0:
        print("No eligible temporary caches.")
    if not quiet and not execute:
        print("Preview only. Add --execute to remove eligible directories.")
    if not quiet and eligible > 0:
        verb = "Would free" if not execute else "Freed"
        print(f"{verb} approximately {human_size(total_bytes)} across {eligible} cache(s).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("path", help="print the shared cache path for the selected Xcode major")
    subparsers.add_parser("status", help="show managed cache paths and disk use")
    clean_parser = subparsers.add_parser("clean", help="preview or clean temporary caches older than 7 days")
    clean_parser.add_argument("--execute", action="store_true", help="delete eligible, unlocked temporary caches")
    run_parser = subparsers.add_parser("run", help="run a build with an explicit, locked DerivedData path")
    run_parser.add_argument("--temporary", metavar="LABEL", help="use an isolated cache, removed after success")
    run_parser.add_argument("command", nargs=argparse.REMAINDER, help="command and arguments after --")
    args = parser.parse_args()

    try:
        if args.action == "path":
            print(shared_path())
            return 0
        if args.action == "status":
            return status()
        if args.action == "clean":
            return clean(args.execute)
        if args.action == "run":
            command = args.command[1:] if args.command[:1] == ["--"] else args.command
            return run_command(command, args.temporary)
    except (RuntimeError, ValueError) as error:
        print(f"build-cache: {error}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    sys.exit(main())
