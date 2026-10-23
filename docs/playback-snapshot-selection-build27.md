# Playback snapshot selection — Build 27 candidate

## Baseline

Based on accepted Build 26, commit `b2baff2c0432ca3e77509cd44ed3cd391c0500c4`.
The user confirmed physical-device testing passed. Background continuation and
the existing frame-pacing fixes are retained. This work uses a separate branch.

## Source-confirmed redundant work

`PlayerStateViewModel.firstUsablePlaybackSnapshotImage` previously accepted a
variadic array of image values. Swift evaluated every candidate expression before
entering the function. Returning the first usable image therefore did not prevent
later surface rasterization or video-buffer conversion on the main actor.

The existing two- and three-candidate calls cover transition snapshots, current
frame snapshot views, surface-readiness confirmation, first-frame fallback and
seek-reveal fallback. Build 27 accepts nonescaping autoclosures instead, invoking
each candidate only after the previous candidate is missing or black. Candidate
priority, black-frame rejection, remembered-image fallback and snapshot
classification remain the same. The seek path's explicit black-surface guard
continues to reject a cached pre-seek frame.

The regression tests exercise the real public snapshot methods with image-read
spies: a usable video image skips the secondary surface read; missing or black
video images still read the current surface; unavailable fresh images preserve
the remembered fallback and its classification. This demonstrates avoided calls,
not a measured reduction in pause/seek latency or display hitches.

## Scope and validation

No buffer/CDN/warmup policy, seek tolerance, 120 ms settle window, 2.4 s fallback,
audio suppression, background-playback policy or rendering pipeline is changed.
The next performance decision still requires same-device recovery traces.

Xcode 26 CI must compile and run the snapshot selection tests, existing seek
reveal/audio-suppression regressions, and Release before a delivery is accepted.
Local environment is Linux and cannot execute UIKit/XCTest or produce an IPA.

Device comparison against Build 26: pause/resume, near/far seek, rapid seeks,
seek while paused, and fullscreen rotation. Check that overlays still show a
usable frame and that no old frame or premature audio is exposed. Report actual
latencies separately from the reduced snapshot-call count.
