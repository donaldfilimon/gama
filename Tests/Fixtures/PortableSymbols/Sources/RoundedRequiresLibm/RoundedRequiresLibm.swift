// NEGATIVE FIXTURE — its emitted object MUST fail the portable-symbol gate.
//
// Deliberately outside every Gama SwiftPM target. This is the expression shape
// that previously left round/rint/trunc/ceil/floor references in GamaCore on
// native Linux and broke the static consumer link. The pinned host compiler
// represents the same dependency class as `_roundSlowPath` in a debug object.
public func gama_negative_roundedRequiresLibm(
    fraction: Double,
    totalEighths: Int
) -> Int {
    Int((fraction * Double(totalEighths)).rounded())
}
