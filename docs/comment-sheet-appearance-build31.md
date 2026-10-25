# Comment sheet appearance alignment — Build 31

Baseline: user-accepted Build 30 head `802eeb6859512373dad024d1f13f5ee01c7be63e`.
Build 30's focused real-device check was accepted on 2026-10-25. Keep its IPA
and draft PR #46 available; do not merge that PR as part of this change.

## Report and code evidence

[Issue #45](https://github.com/Rone89/cilicili/issues/45) reports black comment
text becoming unreadable when the comments sheet expands to full screen.

RootTabView deliberately separates SwiftUI content colorScheme from
preferredColorScheme: a video can request a dark host for status-bar contrast
while content retains the user's light appearance. CommentSheetPresentation
previously specified detents without specifying the presented appearance.
That permits the modal UIKit background/traits and inherited SwiftUI text
appearance to disagree. Expanding to the large detent can expose the mismatch
more clearly. This is a code-derived explanation; reproduction and the exact
issue screenshot still require validation.

## Change

At the shared comment-sheet presentation boundary, read the inherited content
colorScheme and apply it with preferredColorScheme. The modal UIKit appearance
then follows the same appearance used by its SwiftUI comment content, including
changes while open. Both replies and conversation sheets use this boundary.
Do not change RootTabView's video status-bar policy, text colors, body fonts,
line spacing, detents or player behavior.

## Verification

Two network-free UI tests use the production comment-sheet modifier and actual
BiliEmoteText. A debug-only fixture deliberately requests conflicting host and
content appearances, matching the production split. Each test checks the
native label's actual UIKit trait in medium and large detents, then toggles
the content appearance while the sheet remains open. System grabber dragging
must genuinely reach the large detent; screenshots are retained in test results.
The probe and test routing exist only in DEBUG.

Local host has no Swift/Xcode. Local diff review is not compilation or a
passing UI-test claim. Xcode 26 CI must build both Debug tests and the unsigned
Release 1.1.1 (31) package. Inspect the individual new test results, including
any automatic retry; do not infer an initial pass only from the final job state.

After CI, device validation should use both system/app light and dark modes:
open comments and replies over a video, expand and collapse the sheet, and
check body text, usernames, links and emotes. Also check nested conversation/
profile sheets and settings appearance changes, then confirm the underlying
player and status-bar contrast remain correct.

## Device follow-up: app appearance was not followed (2026-10-25)

The user supplied two Build 31 screenshots: the video comment page is light,
but both the reply-list sheet and the reply composer are dark. CI111's two
appearance tests passed, yet the original fixture directly injected colorScheme
inside the sheet. It did not exercise the production presentation boundary, and
it did not cover the independent UIKit composer host. CI111 is not acceptance
of this device issue.

Preserve the resolved app content appearance in a separate optional environment
value at RootTabView, outside the sheet boundary. Read it in the shared sheet
modifier and set both SwiftUI content appearance and native preferred appearance.
The existing video host/status-bar appearance strategy remains intact.

RichCommentComposerPresenter now explicitly transfers that resolved appearance
into its independent UIHostingController's SwiftUI root and native override,
both at creation and subsequent updates. This includes native editor descendants.
Third-party keyboard rendering itself remains outside app-controlled coverage.

The sheet fixture no longer injects colorScheme inside the sheet. Its two
existing tests now compare both actual native UIKit traits and SwiftUI content
appearance, retaining real medium-to-large dragging and live theme toggling.
Two additional tests open the actual production UIKit composer presenter under
opposing host/content appearances, dismiss through its backdrop, toggle the app
content appearance and reopen, checking both native and SwiftUI appearances.

No local Xcode/Swift toolchain is available; the follow-up requires fresh Xcode26
CI results, including all four individual CommentSheetAppearanceUITests.
Keep version/build 1.1.1(31). A replacement IPA is not ready until that head passes
all seven jobs and its package metadata/hash/provenance are verified.
