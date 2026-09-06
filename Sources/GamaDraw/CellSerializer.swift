//  CellSerializer.swift — GamaDraw
//  A terminal reconciles one frame against the last and swaps the planes.
//  A browser DOM and a C-ABI host do not: they read the freshly painted
//  back plane whole, every frame, and never swap. `CellPresenter` names
//  the first family; this names the second.
//
//  The two cannot be one protocol. `CellPresenter.present` takes the
//  buffer `inout` and documents that it "swaps the buffers", while the
//  wholesale consumers reach the grid through
//  `HostPump.advance(into:emit:)`, whose `emit` hands them a *borrow* —
//  no `inout` access can be formed from it, and no swap ever happens.
//  Design record: docs/superpowers/specs/2026-09-06-cell-serializer-design.md

/// Derives a value from a painted ``CellBuffer`` without modifying it.
///
/// This is the wholesale counterpart to ``CellPresenter``. Where a
/// presenter reconciles the back frame against the front and then swaps
/// the planes, a serializer reads the back plane and leaves the buffer
/// exactly as it found it. Every difference in the requirement's
/// signature encodes that:
///
/// - Non-`mutating`, because a serializer holds no frame state. Two calls
///   on an unchanged buffer return the same value.
/// - No swap, and none is implied. A conforming type that advanced the
///   buffer would break ``GamaWASM`` and ``GamaEmbed``, which have never
///   swapped and would begin emitting diffs of themselves.
/// - `borrowing`, matching the parameter that
///   ``HostPump/advance(into:emit:)`` already hands its consumer.
///
/// `CellBuffer` is `Copyable`, so `borrowing` here guarantees no copy is
/// taken and states the intent; it is not a correctness requirement, and
/// a conformance is not made unsound by ignoring it.
///
/// Nothing selects a conformance at run time today: `GamaWASM` always
/// emits HTML and `GamaEmbed` always emits a ``DrawList``. This protocol
/// names a shape shared by two backends; it is not a plug-in point, and
/// should not be described as one.
public protocol CellSerializer {
    /// The value this serializer derives from one painted frame.
    associatedtype Output

    /// Derives this serializer's output from `buffer`'s painted back plane.
    ///
    /// - Parameter buffer: The freshly painted grid, borrowed. The buffer
    ///   is not modified and its planes are not swapped.
    /// - Returns: The derived value for this consumer.
    func serialize(_ buffer: borrowing CellBuffer) -> Output
}

/// Serializes a painted grid to the portable ``DrawList`` vector form that
/// every non-terminal backend consumes.
///
/// This adds no behavior. It gives ``DrawList/from(_:)`` a name in the
/// ``CellSerializer`` family so `GamaEmbed`'s frame path reads as a member
/// of that family rather than as a bare free-function call.
public struct DrawListSerializer: CellSerializer {
    /// Creates a serializer. It holds no state; the buffer owns the frame.
    public init() {}

    /// Returns the ``DrawList`` for `buffer`'s painted back plane.
    ///
    /// Byte-identical to ``DrawList/from(_:)``, which it calls directly.
    /// `CellSerializerTests` pins that equivalence, because a divergence
    /// here would surface only as a failure of the C-ABI decode gate.
    public func serialize(_ buffer: borrowing CellBuffer) -> DrawList {
        DrawList.from(buffer)
    }
}
