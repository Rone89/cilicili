#!/bin/bash
set -euo pipefail

selectors="$(python3 Scripts/ui-test-shards.py --shard "$UI_SHARD" --count 4)"
case "$selectors" in
  *DynamicDetailFlowUITests*) ;;
  *) exit 0 ;;
esac

# Let Xcode start its selected existing simulator through a real, isolated UI
# check. Do not manually boot, create or switch simulators for media preparation.
python3 Scripts/build-cache.py run -- xcodebuild \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "$TEST_DESTINATION" -destination-timeout 120 \
  -resultBundlePath "$RUNNER_TEMP/photo-preflight.xcresult" \
  -only-testing:biliUITests/CommentActionFlowUITests/testReplyActionOpensComposer \
  -parallel-testing-enabled NO -enableCodeCoverage YES \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | \
  tee "$RUNNER_TEMP/photo-preflight.log" | \
  awk '/Test (Case|Suite)|: error:|Fatal error:|\*\* TEST/ { print; fflush() }'

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
# Wait for the simulator Xcode already started; this does not boot a device.
python3 - "$simulator_id" <<'PYTHON'
import os
from pathlib import Path
import subprocess
import sys
import time

simulator_id = sys.argv[1]
root = Path(os.environ["RUNNER_TEMP"])
try:
    subprocess.run(["xcrun", "simctl", "bootstatus", simulator_id], timeout=90, check=True)
    inventory = subprocess.run(["xcrun", "simctl", "list", "devices", "--json"], timeout=30, check=True, capture_output=True)
    (root / "photo-simulator-inventory.json").write_bytes(inventory.stdout)
    with (root / "photo-media-import.log").open("wb") as log:
        for attempt in range(3):
            try:
                result = subprocess.run(["xcrun", "simctl", "addmedia", simulator_id,
                    str(root / "comment-photo-fixture.png")], timeout=45, stdout=log, stderr=subprocess.STDOUT)
                if result.returncode == 0:
                    sys.exit(0)
            except subprocess.TimeoutExpired:
                log.write(b"Photo import timed out; retrying.\n")
                log.flush()
            if attempt < 2:
                time.sleep(5)
except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
    print(f"Photo prerequisite failed: {error}", flush=True)
sys.exit(1)
PYTHON
