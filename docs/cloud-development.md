# Cloud development checks

Pull requests and main pushes use one `iOS CI` workflow. It runs three main independent
checks: all `biliTests` unit tests, all `biliUITests` UI tests across four shards, and an unsigned
device Release build. The two test targets run on separate disposable runners
with matrix fail-fast disabled, so one failure cannot cancel the other target.
The unit target and all four UI shards are required for a complete pass.
`Scripts/ui-test-shards.py` discovers every XCTestCase class containing test
methods, then balances complete classes by method count. It fails on unsupported
class declarations rather than silently omitting tests. Shards use independent
runners and result artifacts; tests remain serial inside each simulator. A separate focused
`interaction-regression` matrix entry gives earlier feedback for dynamic tab
reselection and search dismissal; it does not replace the complete UI target.

## Environment

- Use a disposable `macos-26` GitHub-hosted runner.
- `Scripts/ci-environment.py select-xcode` captures the full version output before
  parsing it and exports an installed Xcode 26.5+ toolchain through `DEVELOPER_DIR`.
  It does not change the host's global Xcode selection or fall back to Xcode 27.
- `select-simulator` selects an already available iPhone on iOS 26.1+ within iOS 26
  by UDID. It never creates, clones, deletes, or manually boots a simulator.
- Both commands require `GITHUB_ACTIONS=true`; they are not local development
  entry points. Local simulator restrictions in `AGENTS.md` remain applicable.
- Build and test commands use the existing managed build cache. Each disposable
  runner has its own cache; no DerivedData is uploaded or shared between jobs.

The app already enables complete strict concurrency checking in the project.
CI does not pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` globally: that also reaches
DanmakuKit, whose warning suppression conflicts with that compiler option.
Changed-file Swift formatting remains advisory, as before.

## Results

Each test check uploads its raw log, an xcresult when produced, and a coverage
report only when xccov successfully generates one. Artifact names identify `unit`
or `ui-1` through `ui-4` and the workflow attempt, so a job rerun retains the first
attempt's evidence without conflicting with its artifact names. Coverage is
reported separately, not as an aggregated project result.
Environment failures do not produce a second failure for a missing artifact.
Execution remains serial within each destination to protect UI fixture state.
XCTest timeouts use a 300-second default and a 600-second maximum per test, so
one stalled case can fail without consuming the entire 60-minute job budget.
The Actions console shows test progress and errors; the uploaded raw log keeps
all compiler output. The pipeline always propagates xcodebuild's exit status.

The Release check uploads a version/build-named unsigned IPA on success and the
existing Release build log on failure. Tags and manual release builds continue
to use `Build unsigned IPA` and its original output location.

An unsigned IPA is a build artifact, not an installable signed test release.
Signing and TestFlight distribution are separate setup work. These workflows
do not access signing credentials, publish releases, or merge pull requests.

## Device acceptance deliveries

For each new device-acceptance delivery, increment `CURRENT_PROJECT_VERSION` in
all project configurations before building. Keep the marketing version unless
the release scope calls for a version change. Never relabel an older IPA as a
new build. The PR Release artifact name includes the version and build read
from the built app's Info.plist. Packaging also emits `build-info.json` and a
SHA-256 checksum alongside the IPA so the delivered binary can be identified.
The user signs and installs the unsigned IPA independently; include a short
plain-language device checklist and report test failures separately.

## Acceptance

1. Run the environment-helper regression tests (also available on Linux):
   `python3 -m unittest discover -s Scripts/tests -v`.
2. Open a PR and confirm both Xcode 26 test targets and Release actually execute.
3. Inspect the xcresult for test outcomes, not just a successful setup step.
4. Confirm the Release artifact is generated before claiming a build is ready.
5. Record any remaining app compilation/test failures independently from the
   environment fix. Simulator success does not establish device performance,
   cellular behavior, or measured energy savings.

## Deterministic UI inputs

The detail UI suite opts into `--ui-test-video-detail-network` in Debug only.
It supplies fixed API responses and the existing test playback engine while
retaining production routes, views, controls and rotation hosts. Release and
normal launches retain their production sessions and media engine. These checks
verify UI state/lifecycle, not real decoding or network performance.

The shard containing DynamicDetailFlowUITests prepares an actual Photos asset.
A cached build-for-testing completes before the bounded media-import window
starts. A launch-only fixture test then lets Xcode start the selected simulator.
The importer observes boot completion with `simctl bootstatus` without its boot
flag, then `simctl addmedia` imports a generated PNG. No simulator is manually booted or
created. The actual photo test selects and removes that image through the system
picker. Preflight diagnostics are uploaded on failure; the complete shard still
runs all its assigned classes. The comment menu and editor assertions remain in
their normal UI test; media preparation does not exercise them. A failed import
or failed launch still fails the photo preparation gate.

Readable failure diagnostics are also exported when a test fails before passing
on retry. A green xcodebuild exit status must not discard evidence of an earlier
application exit or assertion failure.
The launch-only photo preflight allows one Xcode-managed retry, matching the
bounded retry policy of the full UI suite. Its log and xcresult are uploaded even
if that retry passes. Two failed launch attempts or a failed media import still
fail the preparation gate; the full UI suite continues to retain its own results.

Reduced Motion root-tab coverage enables the actual system setting through Settings
and verifies the read-only SwiftUI environment value seen by the mounted subtree.
Restoration resolves the Settings page again because it can return to its root
after the app under test takes focus; it does not reuse a stale switch node. Accessibility text menu
tests long-press a visible intersection of oversized text, not an offscreen
element center. Photo preparation failures remain failures, but the full shard
still executes so unrelated results and readable crash diagnostics are retained.

The recommendation-feedback UI case can explicitly arm its Debug fixture's
three-second notice expiration after observing the actual notice. This avoids
missing the entire transient notice when a system menu tap takes longer than
its lifetime. Other fixture launches retain automatic expiration, and Release
does not include this control. The test still checks the native menu, notice
image/label, expiration and correct card removal. Long presses target the visible
cover. The player-collapse case uses bounded held drags to reach minimum height,
then separately checks relative content scrolling with a small additional drag;
its player-height, header-motion and viewport assertions remain active.
