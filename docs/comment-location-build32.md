# Comment IP-region metadata — Build 32

Baseline: user-accepted Build31 head1745025d70dfb7d3443afd26f5c2f43b2e3b8236.
This is one part of issue10, not completion of the whole feature request.

Decode optional reply_control.location from the existing comment response.
Reference shape: PiliPlus lib/models_new/reply/reply.dart and reply_control.dart.
Preserve the service label, normalize whitespace, and hide absent/blank/wrong-type
metadata without rejecting the surrounding comment. No new requests or device
location access. The value is service-provided IP-region metadata, not a
measurement of a person's present or precise position.

Combine time and region with a middle dot using existing secondary metadata
typography. Video/dynamic comment headers, reply roots, replies and dialog rows
use this metadata. Compact inline reply previews keep their existing layout.
Include normalized location in list/reply cache signatures to invalidate stale
rendered content after an API refresh.

Five unit regressions cover decode/nested replies, missing/null/blank/malformed
data, separator behavior, both display models, and list/reply cache invalidation.
Two UI regressions render the production video/dynamic headers, reply roots,
reply rows and dialogs with four distinct service regions and one missing
region; check all labels and absence of a fabricated fifth label.

No local Swift/Xcode toolchain is available. Local diff/whitespace inspection is
not compilation or test execution. Require fresh Xcode26 CI and individual new
test discovery/results before delivering an unsigned 1.1.1(32) IPA.

Device check: real video and dynamic comments, reply/dialog sheets, missing
metadata, long region labels, light/dark mode and larger text. Retain accepted
Build31/30/29 packages. No playback behavior or appearance policy changes.
