# Video detail frame pacing: Build 21 candidate

## Verified starting point

- User accepted Build 19 on device but reported obvious frame drops in the video detail page. Live device acceptance remains deferred.
- GitHub Build 19 branch: `codex/ui-regression-build19`, head `502be7b089fd3885dd7768559e2ff4dc671b13e8`, tree `d5b236500d35ca03e3c58cf4ef86fb2f9d86564d`, draft PR #35. Main remains `adf2995b61ad402f68d923407bd758f08a359bc6`.
- Existing run 39354263274: Xcode 26 Release succeeded; unit tests ultimately passed with one retry reported in PR #35; focused interaction and UI shards 1, 2, 4 succeeded; UI shard 3 failed. This is not a fully green baseline.
- No subsequent performance-fix commit was present in the remote branch inventory.
- Old `cilicili-build12-restored` workspace has three uncommitted UI test edits (DynamicDetailFlowUITests, DynamicRepliesPaginationUITests, VideoDetailFlowUITests). They were inspected and preserved in place, not included in this change.
- Recovered the exact Build 19 commit metadata and file tree from GitHub into a separate worktree. The reconstructed tree matches the delivered Build 19 source tree exactly.

## Candidate changes and evidence

1. DanmakuKitOverlayView.apply filtered and sorted its input window unconditionally, although it already had an itemsRevision contract. Prepare only on a changed revision, matching the Metal path's existing behavior.
2. DanmakuKitOverlayView.configureRenderer ran on every layout callback and reassigned all renderer settings. DanmakuKit 1.6.0's overlap setter loops through every track, and disabled type setters stop their tracks even on repeated false assignments. Cache the effective frame/settings and assign only changed properties. Continue updating playback speed separately and preserve real viewport/settings changes.
3. LibraryStore.recordPlaybackProgress synchronously JSON-encoded the complete progress dictionary and wrote UserDefaults in the main-actor playback callback. Keep the in-memory resume state immediate; send encoding and persistence to one serial utility queue, ordered across store instances. Keep the schema, key and 240-entry bound. Encoding failures preserve previously stored data.

These are source-confirmed sources of unnecessary work, not a measured diagnosis of the user's complete frame-drop symptom. No device FPS, hitch duration or energy improvement is claimed.

4. Build 20 CI exposed a pre-existing paused Metal frame failure. The renderer drops a draw when a GPU slot or drawable is unavailable, but a paused MTKView has no automatic next tick. Retain the pending refresh until a command is submitted; coalesce bounded asynchronous retries (up to 16 attempts at 16 ms), canceling on resume, suspension, detach, or stop. Classify manual-frame diagnostics at the actual draw callback. Admit a nonblocking GPU buffer slot before requesting a drawable; a busy slot must not enter drawable acquisition. Add a regression with a held slot and a drawable accessor spy, including slot release after unavailable drawables. Strengthen the integration test with deterministic dropped submissions and detach cancellation.

## Verification

- Local `git diff --check`: passed.
- Environment helper regressions: all 7 passed on Linux.
- New XCTest cases cover stable on-screen DanmakuKit cells across 120 repeated updates, revision/settings/viewport refreshes, background encoding, ordered persistence, failed encoding, and resume restoration.
- Build 20 run 39455894935: Xcode 26.6 Release succeeded and all 5 new regression tests passed on their first attempts. AVPlayer recovery timed out once, then passed its configured retry. MetalDanmakuIntegrationTests/testMTKViewActuallySubmitsFramesAndPausesStopsOnWindowDetach failed its paused manual-frame assertion twice; the overall unit job failed and downstream UI jobs were skipped. Build 20 IPA was generated but is superseded by the Build 21 candidate.
- Build 21 adds the paused Metal retry fix and the strengthened integration regression. Its Xcode 26 compilation, XCTest and Release verification are pending. The user explicitly authorized uploading Build 21 and the subsequent changes needed to complete this frame-drop task, updating the draft PR and continuing Xcode 26 builds/tests on 2026-10-21. Build 21 cloud verification is now being resumed; no successful new result is claimed yet.
- Initial submission was blocked by automatic approval review. The user explicitly authorized uploading the reviewed changes, creating an independent branch and draft PR, and using GitHub Actions Xcode 26 builds in the current chat on 2026-10-21. Cloud verification is now pending; no successful new build is claimed yet.

## Delivery

The user authorized remote writes. Draft PR #36 and branch `codex/video-detail-frame-pacing-build20` are based on Build 19. Use the existing Xcode 26 CI selection/cache helpers. Do not merge main. Inspect the Release log and XCTest results, repair any compilation/test failures, then deliver only the newly built unsigned IPA with build number 21 and its checksum.

Device comparison should use the same video and settings in Builds 19 and 21: scroll description/comments during playback with danmaku both enabled and disabled, pause/resume, seek, and rotate to/from fullscreen. Simulator correctness does not establish device performance. Do not expand live device testing.
