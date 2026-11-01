# Overlapping recovery and paused-seek ownership (Build 48)

Device collection exposed two control-flow defects. During a burst of committed
seeks, later requests could be classified as paused even though the burst began
while playing. A seek made while intentionally paused also retained a playing
recovery watchdog, which could reseek roughly three seconds later if playback
was explicitly resumed before that old deadline.

## Changes

- A repeated begin-scrub while a commit is pending preserves the original
  resume intent. An explicit pause still cancels that intent and invalidates
  pending commits. Existing generation checks keep older completions inert.
- Slider/scrub commit pauses and a queued playing callback during a scrub use
  the existing quiet pause path. This pauses AVPlayer and retains temporary
  audio suppression without deactivating the audio session. Explicit pause,
  background and navigation policies remain unchanged.
- Playing recovery tracking is started only for a commit that intends to
  resume playback. Paused commits retain transition metrics but have no stale
  playing-recovery watchdog while paused. An explicit subsequent play starts a
  fresh full watchdog budget against the retained target; stale video can still
  recover and healthy target video resolves that guard. The scrub path cancels the previous seek's
  tracking at the start of a newer commit.

Frame eligibility, advancing-frame checks, the stable reveal window and fallback
deadlines are unchanged. The audio/video reveal guards are not shortened based
on aggregate device timings. Surface recovery is also retained until its cost
and necessity can be evaluated separately.

## Collection changes

Report schema 2 adds optional synchronous pause/play/seek command durations and
a pause hold duration. Existing actualPauseMilliseconds retains its original
definition: command start until the following play request. pauseHoldMilliseconds
isolates the requested hold after the pause command returns. These command spans
are not frame/display/audio-output latencies. The synchronous audio-session
deactivation span is also recorded against the current manual-pause ID, with
a success flag, so its share of a slow explicit-pause command can be measured.

Seek metrics now retain their safe action prefix so an original transition can
be distinguished from its retry/rebuild. A playing-seek completion must carry a
playing-mode recovery metric. Schema 1 reports remain decodable with the new
optional fields absent.

## Verification

Held asynchronous seek completions exercise the real native-progress driver and
PlayerStateViewModel: playing bursts resume at the final target, paused bursts
stay paused, an explicit pause wins, queued playing callbacks re-pause quietly,
and old completions cannot restore a stale target or play intent.

Both slider and scrub paused-seek cases resume before the former watchdog
deadline and reject an early retry from that old deadline. Still-stale video
retains recovery after the fresh full playback budget; healthy target video
resolves its guard without reseeking. Collection tests
separate a simulated 750 ms synchronous pause command from its five-second
hold, verify safe action labeling and preserve schema 1 decoding.

A further on-device run is needed for comparison. No device speedup percentage
is inferred from simulator timing or from the previous small single-video sample.
