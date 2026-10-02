# Gate 8 playback recovery diagnostics

This diagnostic is compiled only for DEBUG. Playback configuration, seek tolerance,
segment alignment, warming, cache, CDN selection, audio session and UI settle policies
are unchanged. Use the existing playback performance log export to collect
`[RecoveryTrace]` events and `[RecoveryTraceSummary]` records.

## Trace boundaries

- `manualResume`: a foreground play request following an explicit pause of an already
  presented item. Startup, navigation/background restoration and item replacement
  clear the manual pause intent. Pause duration starts at the pause request.
- `userSeek`: slider commit. A subsequent commit supersedes the prior trace, while
  outstanding range tickets retain their original trace ID.
- `seekCompletion` is the AVPlayer callback, not a rendered frame. `playing` is
  AVPlayer's actual timeControlStatus, not the UI's optimistic playback state.
- `firstNewFrame` requires a VideoOutput frame whose media timestamp advances past
  the pre-resume playhead. `firstTargetFrame` requires seek completion and a new frame
  within 0.75 seconds of the aligned target; a cached frame at the prior playhead is
  rejected. The existing output and ready-for-display surface are observed without
  image conversion. This is public-API frame availability, not physical screen scanout.
- DEBUG frame observation samples approximately every 16.7ms and stops at the first
  eligible frame, teardown, supersession or a bounded timeout. Very short/same-position
  paused seeks may have no qualifying new frame; unavailable fields remain `-`.
- `uiReveal` marks the application removing its seek overlay/state, not compositor
  presentation. A paused seek may reveal UI before its frame is observed.

## Range evidence

A per-bridge scope tracks opaque resource digests, track, range and request ID. Target
matching uses the existing seek map's target video/audio segment; unrelated ranges are
not substituted when the target request is unobserved. Init requests remain separate.
Cache, joined and network are determined from the existing cache result/callbacks.
`requestedHost` is the canonical route host; `responseHost`, when available, is the
actual source returned by the existing callback. Neither field contains URL queries.

Streaming callbacks can observe actual CDN body bytes. Existing large buffered
`data(for:)` fetches and joined fetches do not expose their original first body byte;
CDN TTFB stays `-` for these cases. Completion/data availability must not be interpreted
as TTFB. Cache availability is a bridge boundary, not a zero-latency network request.
Warm and player range equality does not by itself prove that a joined request was
owned by seekWarm. If ownership cannot be proven it remains unknown.

Local connection closure and upstream request completion are separate events. A local
connection closing does not prove that the underlying CDN task has been cancelled.
The diagnostics never cancel or reschedule any network request. Outstanding previous
requests are counted at the next trace and retain original IDs on late callbacks.

## Device sampling

Use one DEBUG build, one device and the same cellular network/settings:

- Pause 5 seconds, then resume: 5 samples.
- Pause 30 seconds, then resume: 5 samples.
- Pause 120 seconds, then resume: 3 samples.
- Near seek (10–30 seconds either direction): 5 samples.
- Far seek into an unplayed region: 5 samples.
- Rapid seek (4–5 commits in quick succession): 5 rounds.

Keep the app in the foreground for the pause groups. Export logs after the groups.
Compare pause duration/buffer coverage, audio activation, play-to-playing and fresh
frame time. For seeks compare completion, target range source/first byte when available,
surface/audio work, fresh target frame and UI reveal. Do not infer a playback strategy
change from fixture timing or missing TTFB measurements.

## Reveal and shared-task attribution

`uiRevealDecision` records only changes in decision/reason, using the existing checks.
It distinguishes playback gate, missing rendered time, target-window rejection,
black/unavailable surface snapshots, settle start/reset, eligibility and 2.4s timeout
fallback. No extra surface capture, pixel analysis or rendering check is introduced.
The event includes observed frame/target/window values, check/reset counts and elapsed
stable/reveal time when available.

Range `taskID` identifies the actual VideoRangeCache producer or external reservation
gate, not a URLSession task. Exact and containing joins carry the producer ID and its
owner trace/request/origin. CDN candidates have separate cache keys and task IDs.
`warmJoinConfirmed=true` on a `rangeTaskJoined` event proves that candidate joined a
warm-owned producer from the same trace; it does not prove that candidate eventually
won. Cache hits have no active task ID. Unreserved/hedged streaming explicitly has no
shared cache-task identity.

Fast fallback emits `rangeCandidateReady`, `rangeFallbackWinner` and
`rangeFallbackGroupExited` separately. Winner-to-group-exit time measures child
settlement after selection; per-producer completion is separate from the outer warm
request's completion. Request cancellation/retry/scheduling remains unchanged.

## Seek reveal sample gaps

The 120ms reveal settle window now retains a previously verified rendered target
frame when a subsequent VideoOutput sample is absent, playback is still active,
and the current playback time remains inside the existing target window. A missing
sample cannot start the window. An explicitly rejected frame, an out-of-window
playback position, or a new/cleared seek discards the evidence. The 2.4s fallback,
seek tolerances, media warmup and AVPlayer configuration are unchanged.

`uiRevealDecision` reports `reason=verifiedFrameSampleGap` and
`preservedMissingSample=true` when this retention is used. Compare reset counts
and frame-to-reveal time on the same device/network. This addresses UI eligibility;
it does not shorten slow media requests or establish a measured runtime speedup.
