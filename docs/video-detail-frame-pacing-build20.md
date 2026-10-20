# Video detail frame pacing: Build 20 candidate

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

## Verification

- Local `git diff --check`: passed.
- Environment helper regressions: all 7 passed on Linux.
- New XCTest cases cover stable on-screen DanmakuKit cells across 120 repeated updates, revision/settings/viewport refreshes, background encoding, ordered persistence, failed encoding, and resume restoration.
- Swift compilation, new XCTest execution and Xcode 26 Release build: **not yet run**. The current host is Linux; the local Mac workspace connector returns an internal error.
- Initial submission was blocked by automatic approval review. The user explicitly authorized uploading the reviewed changes, creating an independent branch and draft PR, and using GitHub Actions Xcode 26 builds in the current chat on 2026-10-21. Cloud verification is now pending; no successful new build is claimed yet.

## Resume after remote write authorization

Publish only this reviewed candidate to a new development branch based on Build 19, create a draft PR, and use the existing Xcode 26 CI selection/cache helpers. Do not merge main. Inspect the Release log and XCTest results, repair any compilation/test failures, then deliver only the newly built unsigned IPA with build number 20 and its checksum.

Device comparison should use the same video and settings in Builds 19 and 20: scroll description/comments during playback with danmaku both enabled and disabled, pause/resume, seek, and rotate to/from fullscreen. Simulator correctness does not establish device performance. Do not expand live device testing.
