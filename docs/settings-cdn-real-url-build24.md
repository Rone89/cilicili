# Settings CDN connectivity with a real video

The user accepted Build 23 on device, then reported that the advanced-settings
CDN test always said no real playback URL was available. The settings action
called `recommendedSnapshot` without its `playbackURLs` argument, so it always
used the service's bare-host fallback even after successful video playback.

Build 24 resolves a playable BVID/CID from the most recent eligible local
playback-progress record. On a settings test, the existing playback API obtains
the video's current media URLs using the configured account/source. Actual
video/audio and backup URLs are supplied to the existing bounded Range probe;
signed query strings are preserved. No hardcoded sample video, player instance,
full media download, or new persisted signed URL is introduced.

When there is no recorded video, settings asks the user to play one briefly.
Unavailable media and request failures leave the previous recommendation and
selected CDN mode intact. Testing does not pin an automatic configuration to a
manual CDN. Cancellation and a changed network/protocol context prevent stale
results from being applied. Local display state keeps the actual probe timestamp
instead of reconstructing it with the current time on every view update.

Six regressions cover eligible-video selection, signed primary/backup addresses,
fetch-to-probe wiring, unavailable media without bare-host fallback, cancellation,
and restoration of the most recently recorded video after an app restart.
Xcode 26 build/test outcomes and artifact identity are recorded in PR #36.

Device acceptance: play a normal video for at least five seconds, return to
advanced settings, and test CDN connectivity. Expect real-playback results and
the selected automatic/manual mode to remain unchanged. Repeat after restarting
the app; without a playback record expect the guidance message. Live device
testing remains deferred. A connectivity result is not a throughput measurement
or proof that another video uses the same CDN route.
