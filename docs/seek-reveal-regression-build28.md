# Seek reveal timestamp regression — Build 28

Baseline: user-accepted Build 27, commit
`5d844bbde69dbf6ba459a57bfb505d057ed8f736`.

## Confirmed correctness issue

Within a single committed seek, `UserSeekRevealSettling.observe` compared each
rendered timestamp against the first frame only. The sequence 120.00 → 120.08 →
120.02 seconds therefore retained its advancing-frame evidence and original
settle deadline, although the last sample moved backward. This can authorize
reveal using a window whose continuity has been broken. The normal-forward
continuation path already checks the last sample, but an in-target-window frame
bypasses that continuation gate and reaches `observe` directly.

Compare regressions against the last rendered timestamp before checking progress
from the first timestamp. A regression exceeding the existing 1 ms tolerance
reanchors both timestamp and wall-clock evidence and restarts settling. Moving
video requires fresh forward motion; paths that do not require motion restart
the normal settle window. Missing samples after a regression cannot reuse old
motion evidence.

## Scope

This is a correctness fix, not a measured speed improvement. No seek target
window, 120 ms delay, 2.4 s fallback, buffer/CDN policy, background continuation,
audio suppression, snapshot priority or UI layout is changed. Build 27 lazy
snapshot evaluation is retained.

Four regressions cover backward samples still above the initial timestamp,
subsequent missing samples, settling without required motion, and tolerated
sub-millisecond jitter. Existing tests cover normal progression, explicit wrong
frames, new seek reset and progression outside the target window.

Local host is Linux without Swift/Xcode. Xcode 26 CI must compile the candidate,
run XCTest and build an unsigned Release. CI results and any recovered failures
must be recorded separately. Real-device validation should cover near/far and
rapid consecutive seeks, paused seeks, pause/resume and rotation. The user has
accepted Build 27; Build 28 has not yet been device-tested.
