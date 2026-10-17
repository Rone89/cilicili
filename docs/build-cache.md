# Xcode build cache

All managed local Xcode builds share one DerivedData directory per selected Xcode major version:

```text
build/DerivedData/Xcode-26/
build/DerivedData/Xcode-27/
```

The directory is selected from the active `xcodebuild -version`, so changing between Xcode 26 and 27 does not reuse incompatible build products. Debug and Release, simulator and device builds share that version's cache. Xcode still keeps platform/configuration products and dependency inputs in their normal subdirectories, preserving its incremental build behavior. Do not vary the path by commit or experiment name.

## Daily builds

Use the managed wrapper for direct `xcodebuild` commands:

```sh
python3 Scripts/build-cache.py run -- xcodebuild \
  -project bili.xcodeproj \
  -scheme bili \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  build
```

The wrapper adds the official `-derivedDataPath` argument and holds an exclusive lock until the command finishes. The three IPA/archive scripts use this same cache and hold the lock through packaging/export. They keep unsigned IPAs in `build/debug-unsigned-ipa/` and `build/release-unsigned-ipa/`, and signed archives and IPAs in `build/archives/` and `build/distribution-ipa/`. Temporary-cache cleanup never scans those locations.

Opening the project directly in Xcode remains supported and keeps using Xcode's own persistent per-project DerivedData location. The project does not change that user-wide Xcode setting; use the managed command-line entry points for the versioned shared path.

For XcodeBuildMCP, first resolve the same path with `python3 Scripts/build-cache.py path`, then set the session's `derivedDataPath` default to that value. XcodeBuildMCP adds `-derivedDataPath` itself; adding it again in `extraArgs` makes `xcodebuild` fail with a duplicate-option error. Do not overlap two XcodeBuildMCP builds that use the shared path; use a temporary managed command-line build when parallel compilation is necessary.

For simulator development and validation, use the existing local **iPhone 18 Pro Max, iOS 27.0** simulator. Do not create, clone, boot, or switch to another simulator unless the user explicitly asks for it.

GitHub Actions runners are disposable. CI jobs use the same managed wrapper and runner-local DerivedData, without uploading it or sharing it between concurrent jobs. Cloud toolchain selection, checks and artifacts are documented in [cloud development checks](cloud-development.md).

## Parallel or incompatible builds

The default is the shared cache. Isolate a build only when another build must run at the same time or an environment is genuinely incompatible:

```sh
python3 Scripts/build-cache.py run --temporary player-probe -- xcodebuild \
  -project bili.xcodeproj \
  -scheme bili \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  build
```

Each temporary cache has a unique directory under `build/Temp/DerivedData/`. The wrapper holds a lock for that directory and deletes it after a successful command. A failed or interrupted build keeps its cache and diagnostic logs for at least seven days. Avoid running two package/export jobs concurrently if they write the same named IPA or log; temporary DerivedData does not change those release output paths.

## Inspect and clean

```sh
python3 Scripts/build-cache.py status
python3 Scripts/build-cache.py clean
python3 Scripts/build-cache.py clean --execute
```

`clean` previews deletions and estimated disk space. `--execute` removes only marked, direct-child temporary DerivedData directories older than seven days. It validates the project and cache paths, obtains the cache's nonblocking lock, and skips active or unrecognized directories. It does not inspect or remove the shared cache, source code, Git data, IPA files, archives, dSYMs, signing material, device support, or simulator data. Successful managed builds run this same age-based cleanup once at task completion; there is no background cleaner.

## Build entry points

- `Scripts/build-debug-unsigned-ipa.sh` and `Scripts/build-release-unsigned-ipa.sh` share the Xcode-major cache; their IPA outputs remain in their existing directories.
- `Scripts/build-distribution-ipa.sh` shares the cache while keeping timestamped `.xcarchive`, export, log, and IPA outputs in their existing release directories.
- CI uses runner-local DerivedData. Historical validation commands should be run through the managed wrapper so they do not create task-specific permanent caches.
