# Manual pause/resume timing — Build 29

## Accepted baseline

Build 28 (`baded9ace6f378fd417d7247bf33336cfc2ba6bd`) passed real-device
testing. Its seven Xcode 26 CI jobs passed, covering 1,124 unit tests, focused
interaction coverage, four UI-test shards, and an unsigned Release build.

## Measurement gap

The detailed first-new-frame recovery trace is compiled only in DEBUG. The
normal unsigned Release build records seek recovery and startup resume, but does
not separate an ordinary manual pause/resume into a user play request, AVPlayer
transport resuming, and a fresh video frame being observed. This leaves no
Release-device evidence to guide changes to the recovery path.

## Change

Keep a short-lived timing record only after an explicit pause of active video.
Mark the next user play request, the first playing state, and the first sampled
rendered timestamp more than the existing 8 ms freshness margin beyond the
pre-pause frame. Write these phases to the existing player-performance session
and copied diagnostics. After a play tap with a valid baseline, a cancellable
main-actor task samples the existing rendered-time output every 50 ms for at most
5 seconds (also bounded to 100 attempts). It stops on success, timeout, another
pause, seek, background/navigation transition, or player stop. It does not change
the regular UI refresh interval, convert pixels to images, or change buffering,
seeking, audio gating, or playback policy.

The frame endpoint is the first advancing output sample observed by the
short observation window. It is not an exact display-presentation timestamp.
The nominal interval is 50 ms; actual scheduling can be slower. Diagnostics include
`sampleGap` and `maxSampleGap` so scheduling delays remain visible. A missing frame
within the window records `frameObservationTimeout` instead of a frame duration. If no
trustworthy pre-pause rendered timestamp is available, log the play and
transport phases but do not claim a fresh-frame duration. Explicit seeks,
background/navigation transitions, and player stop cancel pending manual
resume timing so unrelated recovery cannot be mislabeled.

Four pure timing tests cover phase separation, the advancement threshold,
missing baseline, and invalid/out-of-order samples. Older persisted performance
sessions remain readable because the new field is optional.

## Device test after CI

Using the same video and connection conditions as Build 28, pause and resume at
least five times, then do three short and three long seeks. Copy diagnostics
from the playback-performance panel after each run. The new manual-resume phases
separate pause duration, tap-to-playing, and tap-to-first-observed-frame; the
existing seek-recovery value reports seek-to-stable-frame. Compare Build 28 and
29 using medians, and keep actual display-presentation timing distinct from the
observed-frame sample.

## Device evidence and precision correction

The 2026-10-24 trace for BV1iPnh6YEsf recorded tap-to-transport/frame pairs
838/2042 ms, 16/1219 ms, and 16/18 ms. The first two frame observations were
about 1204 ms after transport, matching the previous 1.2 s playback refresh.
These samples cannot establish equivalent visible freezes. The bounded 50 ms
observation replaces that coarse measurement; it does not attempt a playback
recovery optimization. CI must pass again before retesting the updated IPA.
