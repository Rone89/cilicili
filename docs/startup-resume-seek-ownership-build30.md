# Startup history correction and user-seek ownership — Build 30

Baseline: Build 29 head `c716a1089d4c38c322bfc1c6e2bd4afd7c7fb9c4`.
Keep PR #44 draft and its verified IPA available while this candidate is tested.

## Confirmed code-path issue

The 20:51 device timeline repeatedly verified the original history target
43.36 seconds after manual resumes at 74 and 87 seconds. Inspection showed
that every `startPreparedPlayback()` could schedule immediate history
correction again. Slider paths cancelled the current task, but a later play
request could rearm it. Tap and step seeks did not share that cancellation.

If the user seeks earlier than the original history target, a pending or
rearmed correction can seek back to that original target. This is a position
ownership bug; it has not been established as the cause of the earlier slow
manual-resume samples.

## Change

Centralize existing startup-correction cancellation in `markUserSeekIntent()`
so tap, step, and scrub paths all cancel pending work. Gate later immediate
correction scheduling on `lastUserSeekAt == nil`, retaining the user's seek
ownership for this view-model session. Remove the two now-duplicate calls.
The original retry sequence remains available before any user seek.

No audio activation, buffer/CDN policy, seek-reveal timing, UI layout or
manual-resume observation cadence changes.

## Verification

Four view-model tests use the existing injected engine spy, exercising the
real scheduled task: initial history correction still runs; an in-flight task
cannot override a tap seek; pause/play cannot rearm it; and step seeks cancel
it too. The spy records absolute history-correction seeks separately from the
user's progress/step seek.

This host has no Swift/Xcode toolchain. Local diff/structural checks do not
count as XCTest or compilation. Xcode 26 CI must compile, run the tests and
build the 1.1.1 (30) unsigned IPA before delivery.

After CI, the focused device case is: reopen a video with a saved position
well into the video, seek to an earlier position, pause and resume repeatedly,
then verify the chosen position is retained. Also check normal history resume
on a fresh video opening. Preserve Build 29's diagnostic timing boundaries.
