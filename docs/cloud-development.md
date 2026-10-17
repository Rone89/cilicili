# Cloud development checks

Pull requests and main pushes use one `iOS CI` workflow. It runs two independent
checks: the complete Debug test scheme with coverage, and an unsigned device
Release build. A failing test does not hide the Release build result.

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

The test check uploads its raw log, an xcresult when produced, and a coverage
report only when xccov successfully generates one. Environment failures do not
produce a second failure for a missing coverage artifact. Test execution is
serial to keep UI fixtures and simulator/GPU resources on one destination.

The Release check uploads `cilicili-pr-release-unsigned-ipa` on success and the
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
2. Open a PR and confirm both Xcode 26 checks actually execute.
3. Inspect the xcresult for test outcomes, not just a successful setup step.
4. Confirm the Release artifact is generated before claiming a build is ready.
5. Record any remaining app compilation/test failures independently from the
   environment fix. Simulator success does not establish device performance,
   cellular behavior, or measured energy savings.
