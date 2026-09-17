// NEGATIVE FIXTURE — must produce `#UnavailableSendableConformance`.
//
// Deliberately outside every SwiftPM target; driven by
// `scripts/check-boundaries.sh`.
//
// MEASURED 2026-08-27 on the pinned 6.5-dev snapshot: a `@retroactive
// @unchecked Sendable` conformance to a type with an unavailable Sendable
// conformance is a WARNING, not an error. The signal-redesign spec claimed
// the unavailable conformance "prevents the conformance from ever being
// retroactively fixed by a consumer" — that is overstated. What it
// actually buys is a named, attributable diagnostic that points back at
// the declaration, which a consumer must silence deliberately rather than
// stumble into. Signal now also declares `~Sendable`; the two spellings are
// intentionally complementary, and `check-boundaries.sh` requires both.
// This fixture pins the real diagnostic behavior so nobody re-derives the
// stronger claim from the spec text.
import GamaCore

extension Signal: @retroactive @unchecked Sendable {}
