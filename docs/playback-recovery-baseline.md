# Pause and seek recovery baseline (Build 46)

This change adds Release evidence before changing recovery or buffering policy.
No device baseline has been measured yet. Simulator results do not establish
decode speed, network performance, or energy use.

## Evidence and limits

- Each completed seek transition and its recovery/retry/rebuild carry the same
  sampleID. Manual pause, play request, transport-playing, and advancing video
  timestamp carry one sampleID. Each new operation gets a fresh ID.
- sampleBuild identifies the producing app build. exportApp and exportRunID
  describe the export process only; persisted older sessions retain their own
  sampleBuild or have no such field.
- At request time, targetLoadedRange is covered, uncovered, or unknown.
  loadedAheadSeconds joins overlapping/adjacent ranges but stops at any gap.
  Ranges and targets use the existing display-time coordinate system.
- The extra manual/tap/step observation reads only player time, duration, rate,
  and loaded ranges. It does not read/copy a video frame or start another poll.
  Slider/scrub reuse their existing request snapshot.
- Loaded ranges are AVPlayer evidence, not disk-cache hits or proof that new
  network data is needed. mediaCacheState stays unknown. Invalid/unavailable
  evidence is unknown with a missing duration, never an invented zero.
- mode distinguishes manualResume, seekPlaying, and seekPaused. A paused seek's
  engine completion is not moving-video recovery.
- Existing seek total/engine and manual pauseToPlay/playToTransport/playToFrame
  timings retain their definitions. Manual advancing-frame sampling is 50 ms
  with sample-gap diagnostics. These are video-output timestamp observations,
  not photons/display-presentation timing.
- Request/recovery messages retain the last 16 parts per category. Export after
  each block of three trials. This is bounded diagnostic history, not a complete
  analytics archive.
- Superseded async seeks can exit before producing a completed transition.
  Judge continuous dragging by the final committed target and its UI/audio
  behavior; do not calculate success rates from only retained completed samples.
- A recovery retry keeps the original sample ID/classification; its existing
  total timer starts at that recovery attempt. Do not interpret retry total as
  end-to-end time from the original drag.

## Device collection

Keep the same device, video, selected quality, network, and experiment settings
for comparisons. Note actual device model and those settings with each export.
Do not deliberately disconnect to estimate a fixed buffer duration.

For each block, run three trials and immediately copy the playback performance
log. Avoid unrelated playback between the trial and export.

| Block | Action | Record |
| --- | --- | --- |
| Pause 5 s | Pause, wait about 5 s, resume | Delay, unexpected frame/audio behavior |
| Pause 30 s | Repeat at about 30 s | Same |
| Pause 120 s | Repeat at about 120 s | Same |
| Nearby seek | Seek a short distance | Same, classify from loaded-range evidence |
| Distant seek | Seek far from the playhead | Same, do not assume cache miss |
| Paused seek | Pause, drag, keep paused, then resume | No unintended playback/audio |
| Continuous seek | Commit several different targets rapidly | Final target wins; no stale frame or early audio |

Record exact waits as observations rather than assuming that every range or
pause falls into the expected category. Collect comparison samples only after
the baseline is available; no speedup percentage is claimed by this build.

## Verification

New unit coverage checks unknown versus uncovered evidence, malformed inputs,
range boundaries, overlap/adjacency/gaps, distinct operation IDs, bounded export
history, and pre-seek range capture without starting paused playback. The
existing moving-frame reveal regression also checks request/recovery ID and
classification consistency. Full unit/UI/interaction CI and unsigned Release
packaging remain required before device delivery.
