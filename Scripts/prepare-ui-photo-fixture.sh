#!/bin/bash
set -euo pipefail

selectors="$(python3 Scripts/ui-test-shards.py --shard "$UI_SHARD" --count 4)"
case "$selectors" in
  *DynamicDetailFlowUITests*) ;;
  *) exit 0 ;;
esac

python3 - <<'PY'
import os
from pathlib import Path
import struct
import zlib

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

row = b"\0" + bytes([220, 70, 80, 255]) * 64
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(row * 64)) + chunk(b"IEND", b"")
Path(os.environ["RUNNER_TEMP"], "comment-photo-fixture.png").write_bytes(png)
PY
simulator_id="${TEST_DESTINATION##*id=}"
[[ "$simulator_id" =~ ^[0-9A-Fa-f-]{36}$ ]]
# Import while Xcode owns the running simulator; Xcode may shut it down
# immediately after the preflight finishes. Never boot a simulator ourselves.
python3 - "$simulator_id" <<'PYTHON' &
import json
import os
from pathlib import Path
import subprocess
import sys
import time

simulator_id = sys.argv[1]
root = Path(os.environ["RUNNER_TEMP"])
deadline = time.monotonic() + 600
with (root / "photo-media-import.log").open("wb") as log:
    while time.monotonic() < deadline:
        try:
            inventory = subprocess.run(
                ["xcrun", "simctl", "list", "devices", "--json"],
                timeout=30, check=True, capture_output=True)
            (root / "photo-simulator-inventory.json").write_bytes(inventory.stdout)
            devices = json.loads(inventory.stdout)["devices"]
            is_booted = any(device["udid"] == simulator_id and device["state"] == "Booted"
                            for group in devices.values() for device in group)
            if is_booted:
                result = subprocess.run(
                    ["xcrun", "simctl", "addmedia", simulator_id,
                     str(root / "comment-photo-fixture.png")],
                    timeout=45, stdout=log, stderr=subprocess.STDOUT)
                if result.returncode == 0:
                    log.write(b"Imported photo into Xcode-selected running simulator.\n")
                    sys.exit(0)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
            log.write(f"Photo import not ready: {error}\n".encode())
        log.flush()
        time.sleep(2)
sys.exit(1)
PYTHON
media_import_pid=$!
trap 'kill "$media_import_pid" 2>/dev/null || true' EXIT

# Only verify fixture launch here. Composer interaction is covered by its normal
# UI test and must not be a prerequisite for importing a Photos asset.
# Let Xcode start its selected existing simulator; never boot or create one here.
set +e
python3 Scripts/build-cache.py run -- xcodebuild \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "$TEST_DESTINATION" -destination-timeout 120 \
  -resultBundlePath "$RUNNER_TEMP/photo-preflight.xcresult" \
  -only-testing:biliUITests/SimulatorPreflightUITests/testFixtureLaunches \
  -retry-tests-on-failure -test-iterations 2 \
  -parallel-testing-enabled NO -enableCodeCoverage YES \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | \
  tee "$RUNNER_TEMP/photo-preflight.log" | \
  awk '/Test (Case|Suite)|: error:|Fatal error:|\*\* TEST/ { print; fflush() }'
preflight_status=$?
set -e

# Keep evidence of the first launch failure even when Xcode's one retry passes.
if awk '/Test Case .* failed \(/ || /Restarting after unexpected exit/ { found=1 } END { exit !found }' "$RUNNER_TEMP/photo-preflight.log"; then
  echo "had_test_failures=true" >> "$GITHUB_OUTPUT"
fi
if [ "$preflight_status" -ne 0 ]; then
  exit "$preflight_status"
fi

wait "$media_import_pid"
trap - EXIT
