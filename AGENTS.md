# Xcode build cache rules

Follow [the build-cache guide](docs/build-cache.md) for every Xcode build, test, archive, or IPA workflow.

- Reuse `build/DerivedData/Xcode-<major>` across commits, tasks, Debug/Release, simulator, and device builds. Resolve the active path with `python3 Scripts/build-cache.py path`.
- For command-line Xcode work, use `python3 Scripts/build-cache.py run -- xcodebuild ...`; it supplies `-derivedDataPath` and serializes writers. The existing `Scripts/build-*.sh` entry points do this automatically.
- Do not create a permanent DerivedData directory named after a task, experiment, branch, or commit. Do not clean the shared cache as routine maintenance.
- Use `python3 Scripts/build-cache.py run --temporary <label> -- xcodebuild ...` only for a parallel task or a real cache conflict. It uses `build/Temp/DerivedData/`, removes the cache on success, and retains a failed cache for diagnosis.
- Run `python3 Scripts/build-cache.py clean` to preview eligible temporary-cache cleanup. Add `--execute` to remove marked, unlocked caches older than seven days. Never manually delete an active cache or use this tool to remove release artifacts.
- With XcodeBuildMCP, set the session `derivedDataPath` to the output of `python3 Scripts/build-cache.py path` before building; the tool injects that option itself, so do not repeat it in `extraArgs`. Do not start another build against the shared path until it finishes. Keep parallel builds on separate temporary paths.
- For simulator development and validation, use only the existing local iPhone 18 Pro Max simulator running iOS 27.0. Do not create, clone, boot, or switch to another simulator unless the user explicitly requests it.
- Keep `.xcarchive`, IPA, dSYM, signing configuration, and release files in their existing release locations. Do not change signing identity, profiles, bundle identifiers, or release settings as part of cache work.
