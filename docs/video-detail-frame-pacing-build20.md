# Video detail frame pacing and reply loading

## Verified starting point

- User accepted Build 19 on device but reported obvious frame drops in the video detail page. Live device acceptance remains deferred.
- GitHub Build 19 branch: `codex/ui-regression-build19`, head `502be7b089fd3885dd7768559e2ff4dc671b13e8`, tree `d5b236500d35ca03e3c58cf4ef86fb2f9d86564d`, draft PR #35. Main remains `adf2995b61ad402f68d923407bd758f08a359bc6`.
- Existing run 39354263274: Xcode 26 Release succeeded; unit tests ultimately passed with one retry reported in PR #35; focused interaction and UI shards 1, 2, 4 succeeded; UI shard 3 failed. This is not a fully green baseline.
- No subsequent performance-fix commit was present in the remote branch inventory.
- The initial audit found three uncommitted UI test edits in the old `cilicili-build12-restored` workspace (DynamicDetailFlowUITests, DynamicRepliesPaginationUITests, VideoDetailFlowUITests). Those edits were inspected and preserved separately, and were not included in Build 21.
- Recovered the exact Build 19 commit metadata and file tree from GitHub into a separate worktree. The reconstructed tree matches the delivered Build 19 source tree exactly.

## Candidate changes and evidence

1. DanmakuKitOverlayView.apply filtered and sorted its input window unconditionally, although it already had an itemsRevision contract. Prepare only on a changed revision, matching the Metal path's existing behavior.
2. DanmakuKitOverlayView.configureRenderer ran on every layout callback and reassigned all renderer settings. DanmakuKit 1.6.0's overlap setter loops through every track, and disabled type setters stop their tracks even on repeated false assignments. Cache the effective frame/settings and assign only changed properties. Continue updating playback speed separately and preserve real viewport/settings changes.
3. LibraryStore.recordPlaybackProgress synchronously JSON-encoded the complete progress dictionary and wrote UserDefaults in the main-actor playback callback. Keep the in-memory resume state immediate; send encoding and persistence to one serial utility queue, ordered across store instances. Keep the schema, key and 240-entry bound. Encoding failures preserve previously stored data.

These are source-confirmed sources of unnecessary work. The user later reported improved video-detail frame drops on Build 21. There are no numerical device FPS, hitch-duration or energy measurements.

4. Build 20 CI exposed a pre-existing paused Metal frame failure. The renderer drops a draw when a GPU slot or drawable is unavailable, but a paused MTKView has no automatic next tick. Retain the pending refresh until a command is submitted; coalesce bounded asynchronous retries (up to 16 attempts at 16 ms), canceling on resume, suspension, detach, or stop. Classify manual-frame diagnostics at the actual draw callback. Admit a nonblocking GPU buffer slot before requesting a drawable; a busy slot must not enter drawable acquisition. Add a regression with a held slot and a drawable accessor spy, including slot release after unavailable drawables. Strengthen the integration test with deterministic dropped submissions and detach cancellation.

## Verification

- Local `git diff --check`: passed.
- Environment helper regressions: all 7 passed on Linux.
- New XCTest cases cover stable on-screen DanmakuKit cells across 120 repeated updates, revision/settings/viewport refreshes, background encoding, ordered persistence, failed encoding, and resume restoration.
- Build 20 run 39455894935: Xcode 26.6 Release succeeded and all 5 new regression tests passed on their first attempts. AVPlayer recovery timed out once, then passed its configured retry. MetalDanmakuIntegrationTests/testMTKViewActuallySubmitsFramesAndPausesStopsOnWindowDetach failed its paused manual-frame assertion twice; the overall unit job failed and downstream UI jobs were skipped. Build 20 IPA was generated but is superseded by the Build 21 candidate.
- Build 21 run 39461070316: Xcode 26.6 Release and all 1104 unit tests passed, with zero unit failures or retries. The strengthened paused Metal regression passed on its first attempt. UI shards 1, 2 and 4 passed; UI shard 3 and interaction-regression failed the existing dynamic replies initial-load assertion before any profile tap.
- Build 21 source tree: `b7f3ba028db11735c19495449ee832be4f117b37`, head `6aeac77ad32f054e808aecec8ba1c0afa711caac`. The delivered unsigned IPA is version 1.1.1 build 21, SHA-256 `097bae5d73890596fda6843640f47be77ecf95fff6920b989f08f05520f4b669`.

## Reply-loading follow-up

The isolated Xcode 26 UI probe in run 39529655455 reproduced the initial-load failure. Local fixture requests reached `/x/v2/reply/reply`, but the failed attempts did not deliver decoded replies to the store before the test ended. A successful attempt delivered 12 replies and completed the avatar and mention interactions. This points to the loading pipeline rather than a deterministic broken profile route.

Both replies and dialog requests used `URLSessionTask.lowPriority`, which also selects a detached `.background` JSON decoding task in `BiliAPIClient.decode`. The candidate uses `defaultPriority`, matching the visible top-level comments request and keeping decoding at utility QoS. The fixture, UI assertions, pagination and profile presentation remain the same. Temporary request/state tracing stays on the diagnostic branch and is excluded from the delivery.

Xcode 26 run 39531243594 repeated both unchanged UI cases three times with a fresh runner process for each repetition, without failure-triggered retries: all 6 runs passed with zero failures. A captured iteration delivered page 1 to the store about 0.3 seconds after request submission. This is local-fixture simulator timing, not a production network benchmark. Full unit/UI and Release results, including any failures, are recorded in [PR #36](https://github.com/Rone89/cilicili/pull/36).

## Build 23 network-session lifetime follow-up

Build 22 run 39532665895 ultimately passed after rerunning photo preparation;
all 1104 unit tests passed without retries. A RootTabScroll UI case passed on
retry after its first launch exited. Its archived crash report captures the
exit at 02:56:59 UTC: SIGABRT in NSURLSession task creation, called by
`BiliNetworkRetry.dataOnce` from `PlaybackCDNProbeService.probe`.

The pool returned a raw session under a lock, then invalidated it outside the
lock during a network-path refresh. A borrower could therefore create a task
on an already-invalidated session. Build 23 lends a retained session generation
instead. Refresh switches the pool to a new generation immediately; the old
generation is invalidated only when its last borrower releases it. Retry attempts
acquire the current generation independently. Buffered and first-byte streaming
requests also retain their lease across suspension and response consumption.

Four regressions cover probe and buffered task creation after refresh, eventual
invalidation after the last borrower, and 24 concurrent borrowed requests with
path refreshes. CI photo preparation now checks fixture launch independently
from comment-editor interaction, and retains readable diagnostics even when a
failed test later passes its configured retry. Xcode 26 validation results will
be recorded in PR #36; these changes alone do not establish device crash rates.

## Current delivery

Draft PR #36 and branch `codex/video-detail-frame-pacing-build20` are based on Build 19. Main remains unmerged. Device acceptance builds use the existing Xcode 26 selection/cache helpers and increment all project build configurations together; the session-lifetime candidate is version 1.1.1 build 23. Deliver an IPA only after verifying its embedded build number, source commit, architecture, unsigned status and checksum.

Device comparison should use the same video and settings in Builds 19 and 21: scroll description/comments during playback with danmaku both enabled and disabled, pause/resume, seek, and rotate to/from fullscreen. Simulator correctness does not establish device performance. Do not expand live device testing.
