# Cloud development checks

Pull requests and main pushes use one `iOS CI` workflow. It runs three main independent
checks: all `biliTests` unit tests, all `biliUITests` UI tests, and an unsigned
device Release build. The two test targets run on separate disposable runners
with matrix fail-fast disabled, so one failure cannot cancel the other target.
Both test targets are still required for a complete pass. A separate focused
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
report only when xccov successfully generates one. Artifact names end in `unit`
or `ui`; coverage is reported separately, not as an aggregated project result.
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
   `python3 -m unittest discover -s Scripts/tests -p 'test_ci_environment.py' -v`.
2. Open a PR and confirm both Xcode 26 test targets and Release actually execute.
3. Inspect the xcresult for test outcomes, not just a successful setup step.
4. Confirm the Release artifact is generated before claiming a build is ready.
5. Record any remaining app compilation/test failures independently from the
   environment fix. Simulator success does not establish device performance,
   cellular behavior, or measured energy savings.
