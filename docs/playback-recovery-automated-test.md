# Automated on-device recovery collection (Build 52)

Build 52 adds an idle-deactivation play/pause boundary scenario: **33 trials**
in the full plan, or **3 trials** via “暂停边界短测（3次）”. Report schema is 4;
`context.testPlan` distinguishes `full` from `pauseBoundary`. See
[the Build 52 boundary guide](playback-recovery-pause-boundary-build52.md).
Build 50 introduced three rapid pause/play scenarios for 30 trials and schema 3.
See [rapid recovery collection](playback-recovery-rapid-build50.md). The original
seven scenarios and their timing/evidence semantics below remain in the plan.

From Build 56, first enable “显示自动恢复测试入口” in Mine > Developer and diagnostics; the switch defaults to off. Open a recorded video of at least five minutes, let its first frame appear,
then choose More playback settings > Automatic recovery test > Start.
The original seven scenarios run three times: pause 5/30/120 seconds,
near/distant seeks, paused seek, and a burst of three committed seeks. Normal
duration is around twelve minutes. The app stays foreground and temporarily
holds the existing idle-timer setting; it restores that setting on exit.

The script uses the production pause, explicit play, begin-scrub and committed
native-progress methods. These are semantic commands, not injected touch events.
Actual AVPlayer playback, recovery watches, frame gates, audio suppression and
surface handling are retained. No buffering/cache/recovery policies are changed.

## Evidence

- Each trial retains its own bounded event records from the existing Release
  metrics, independent of the short general-performance history.
- Resume completion requires a play-request ID and a matching advancing-frame
  record with a finite measured latency. Seek completion requires the last
  requested target's transition ID and matching recovered record.
- Earlier continuous-seek targets cannot stand in for the final committed target.
- Paused seek verifies paused intent/state before explicitly requesting play and
  observing subsequent progress. It does not claim a moving-frame or audio-output
  timestamp while paused.
- Timeouts/missing evidence remain distinct from observed outcomes; they are
  never converted into zero latency or a passing result.
- Observed means the required evidence was collected. No latency threshold,
  screen-presentation, audible-output, black-frame or actual-touch assertion is
  implied. Receipt time is labeled separately from measured recovery timings.
- Preparation seeks reset the playhead and may warm buffers. Actual loaded-range
  evidence is retained; this run cannot establish cold-cache performance or
  prove disk-cache reuse. Test settings and media context accompany the report.

## Ownership and interruption

Stopping, leaving the test page, navigation/player stop, app deactivation, audio
interruption, source/rate changes, or network-class changes end the run. A
generation guard invalidates suspended work and old callbacks. Cancellation does
not issue a command to a replacement player/source. There is no automatic restart
on foreground return. Completion pauses the current test player.

Only the latest run is kept. Off-main serial atomic writes checkpoint completed
and current trial evidence. A newer run owns the report slot; an older run cannot
overwrite it. Disk revisions reject stale writes even after a newer failed write.
A report loaded in running state after process termination is marked interrupted.
Write errors keep a copyable in-memory report and display a save warning.

Copy/share the report on the test page. A retained report is also accessible under
Mine > Developer and diagnostics > Playback and network diagnostics > Automatic
recovery test report. No automatic upload is performed. Event fields are
allowlisted; source identity stays in memory and is not exported.

## Validation

Virtual-clock tests execute the complete unshortened 33-trial plan, including
all 465 seconds of requested pauses, without making the CI suite wait in real
time. Additional regressions cover final-target matching, missing evidence,
paused auto-play violations, cancellation/restart ownership, interruptions,
preparation timeouts, invalid input, report durability/revision guards, write
errors, credential exclusion and real idle-timer restoration.

Three UI cases exercise the actual menu/test page: ordinary 120-second fixture
video must be blocked; an explicit Debug-only long-video fixture can start,
stop and copy an interrupted full or boundary-short report. The fixture does not bypass runner logic
or produce measured-device performance results. Real-device measurements remain
the user's next acceptance step.
