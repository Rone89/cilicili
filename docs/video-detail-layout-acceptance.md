# Video Detail Layout Acceptance

Base: `e12c92d`. Build: 472. Xcode 26.6 (17F113), iOS 26.5 simulator SDK, deployment target 26.1.

## Changes

- Portrait reserves the root's actual top safe area once. Landscape and portrait fullscreen retain the full root bounds.
- The nested surface hosting controller no longer subtracts another safe area. The outer surface, player and item ownership are unchanged.
- Content uses the actual embedded player height. A native pinned Section header places the picker after the existing summary/actions and before recommendations/comments. Both tab scroll trees stay mounted; inactive content is excluded from hit testing and accessibility.
- Debug geometry identifies root, window, surface and layer coordinate spaces. Layer geometry is logged separately after layer layout; the surface callback may precede the deferred layer update and must not be treated as its final frame.
- No gravity policy, playback address, network, rotation timing or attach/detach implementation changes.

## Measured Geometry

Real network media: `BV1xx411c7mD`, presentation size 512 x 384. Natural-size asynchronous diagnostic did not produce a value in the captured run; no inferred naturalSize is reported.

| iPhone 17 Pro | Before | After |
| --- | --- | --- |
| Portrait root | 402 x 874 | 402 x 874 |
| Portrait player (root) | (0, 0, 402, 226) | (0, 62, 402, 226) |
| Portrait drawable/layer | 402 x 164 | 402 x 226 |
| Landscape root/player | 874 x 402 | 874 x 402 |
| Landscape surface/drawable/layer | 750 x 382 | 874 x 402 |
| Landscape surface (window) | not archived | (0, 0, 874, 402) |
| Landscape videoRect (layer) | not archived | (169, 0, 536, 402) |
| Gravity | resizeAspect | resizeAspect |

The repaired landscape videoRect reaches the bottom of the root. Symmetric horizontal aspect-fit margins remain intentional. Black-frame duration is unmeasured (`null`), not zero. This is layout evidence, not an Instruments performance result.

## Evidence

- Before: `/tmp/cilicili-geometry-settled.xcresult`, exported diagnostics `/tmp/cilicili-geometry-settled-logs`.
- After iPhone: `/tmp/cilicili-layout-acceptance-phone2.xcresult`, diagnostics `/tmp/cilicili-layout-phone2-logs`.
- Portrait screenshot: `/tmp/cilicili-layout-phone2-images/E52FCF5F-A122-4A1B-839F-C1402EBC3FF5.png`.
- Landscape screen screenshot: `/tmp/cilicili-layout-phone2-images/FC4026D8-7889-43E1-AA54-075291EF2306.png`.
- Scrolled pinned header: `/tmp/cilicili-layout-phone2-images/C31A8749-9BE2-4CD6-B258-BD5C82D27FF3.png`.
- iPad screenshots: `/tmp/cilicili-layout-ipad-images/`, result `/tmp/cilicili-layout-acceptance-ipad.xcresult`.

Temporary artifacts are local and are not committed. Screenshots were visually inspected; full-screen captures use XCUIScreen rather than app-oriented captures.

## Validation

- Debug build succeeded through test builds. Release arm64 simulator build succeeded, `/tmp/cilicili-layout-release-final.log`.
- Full unit suite: 669 executed, 666 passed, 3 existing typography failures; `/tmp/cilicili-layout-final-unit.xcresult`. Updated collapsed-height test and new portrait/fullscreen geometry test passed.
- iPad Pro 11-inch (M5), iOS 26.5: VideoDetail UI 10/10 passed before the final collapsed-height adjustment and test gesture correction.
- First iPhone suite: 8/10 passed. Initial-buffering test assumed auto-hidden controls remained visible; exit test used a center swipe and did not wait for portrait window geometry. Tests now reveal controls and use a true edge gesture after checking the window, without removing final assertions.
- Final iPhone rerun: 9/10 passed, `/tmp/cilicili-layout-phone-final.xcresult`. Initial-buffering controls passed. `testVideoDetailExitDuringRotationReturnsToHomeWithoutRebuildingPlayer` failed the portrait-window expectation after rapid direction changes. This remains an unresolved rotation acceptance item, not a passing result or a proven baseline failure. No rotation lifecycle changes were made to hide it.
- Final iPad rerun: 9/10 passed, `/tmp/cilicili-layout-ipad-final.xcresult`. Fullscreen roundtrip failed when `ui.player.back` disappeared between existence checking and tapping (auto-hidden chrome). The prior 10/10 does not supersede this final failure. Full UI acceptance is incomplete.
- Initial Release build and separate unit build hit exhausted disk space. Only temporary build products were removed. Subsequent Release passed. Unit execution completed, but Xcode's automatic simctl diagnostic hung; terminating that diagnostic allowed the result bundle to close with all 669 results.
- Final build logs contain no compiler warning lines. UI results still report publishing-during-view-update runtime warnings; absence of compiler warnings does not establish absence of runtime issues.

Known baseline failures in `PlayerFormalPlaybackConfigurationTests`:

1. `testNativeTypographyMapsRolesToSystemStylesAndConservativeWeights`: Subhead versus Body.
2. `testNativeTypographyUsesPreferredUIKitFontAndResetsRichTextLineSpacing`: 15 versus 17.
3. `testRetiredTypographyKeyDoesNotChangeNativeTypography`: 15 versus 17.

## Commands

All commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, project `bili.xcodeproj`, scheme `bili`, `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`.

```sh
xcodebuild -project bili.xcodeproj -scheme bili -configuration Debug -destination 'id=68843E67-096A-45DF-BF4E-F39DA74E6FC4' -parallel-testing-enabled NO -only-testing:biliTests test
xcodebuild -project bili.xcodeproj -scheme bili -configuration Debug -destination 'id=68843E67-096A-45DF-BF4E-F39DA74E6FC4' -parallel-testing-enabled NO -only-testing:biliUITests/VideoDetailFlowUITests test
xcodebuild -project bili.xcodeproj -scheme bili -configuration Release -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

## Remaining Boundaries

UIKit still owns the stable AVPlayer surface and system rotation bridge. No lifecycle refactor was performed. Current UI tests do not prove every identity invariant across every frame; recorded sample attach/detach counters are zero during rotation, but this is not a comprehensive leak or black-frame test. Physical devices, VoiceOver, Stage Manager, source-video border analysis, Instruments and prolonged playback remain unverified in this round.
