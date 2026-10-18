# Credential storage and recovery (build 6)

Implements G03 from the 2026-10-18 development plan. This branch follows build 5;
CI validation and device acceptance remain required before delivery.

Normal Debug and Release builds use Security.framework. Update/add/read/delete
errors propagate, including missing entitlements; no path writes a new credential
to UserDefaults. Keychain items use AfterFirstUnlockThisDeviceOnly so background
audio can access credentials after the first device unlock, without iCloud sync.

Existing `<service>.Fallback.<key>` values are migrated on read only when the
secure item is absent. A successful secure write removes that matching plaintext
copy. A valid secure item wins over an old copy. Migration or deletion failure
preserves the original copy for a controlled retry instead of silently losing an
account. Existing copies may therefore remain until secure access succeeds; they
are not used directly as successful reads when Keychain is inaccessible.

Session loading records storage failures and avoids rewriting a partial account
registry. My page shows an error and a retry action. Until recovery succeeds,
new login, registry persistence and logout are blocked with a readable error,
protecting unloaded accounts from being replaced. Existing login views already
surface thrown save errors. A failed initial credential write does not replace
an active account's in-memory credentials.

This does not make multiple independent Keychain items a transactional database.
A later failure in a multi-key write is surfaced, but partial secure writes can
remain and must be checked through retry/relaunch. Error text contains status
codes and recovery guidance, never cookie/token values. No remote reporting or
signing configuration changes are introduced.

Tests opt explicitly into an in-memory Security replacement; there is no automatic
entitlement fallback, simulator detection, or service-name trigger in production.
The 12 KeychainStore tests inject Security failures, verify legacy migration and
retry, accessibility class, account-registry preservation and active credentials.
Full multi-account tests continue through the injected storage implementation.

Device acceptance after cloud validation: login/relaunch, switch purpose accounts,
lock-screen audio after first unlock, logout/relaunch. For an existing install,
check that the expected account survives the upgrade. Missing signing entitlements
should show a storage error rather than a login that disappears after restart.
