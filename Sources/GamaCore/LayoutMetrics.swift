//  LayoutMetrics.swift — GamaCore
//  What LayoutEngine cannot compute itself, injected as a struct of
//  closures rather than a protocol: GamaCore compiles for Embedded Swift,
//  which forbids existentials (`any P`), and a generic LayoutEngine would
//  ripple into every backend. Closures are the house pattern already
//  (BuildContext.registerAction, registerNativeRegion).

/// Supplies the measurements `LayoutEngine` cannot compute itself: how
/// large text renders, how an authored cell length converts to layout
/// units on one axis, how thick a divider is, and how large a registered
/// control measures. `.cell` reproduces today's cell-space layout
/// byte-for-byte; a host with its own text metrics and point grid
/// supplies a different value.
public struct LayoutMetrics {
    /// Size of `text` drawn in `style`, wrapped to `width` layout units
    /// when given (`nil` measures unwrapped).
    public var textSize: (_ text: String, _ style: TextStyle, _ width: Int?) -> Size
    /// Converts an authored length of `cells` cells to layout units on
    /// `axis`.
    public var units: (_ cells: Int, _ axis: Axis) -> Int
    /// Main-axis thickness of a divider, in layout units.
    public var dividerThickness: Int
    /// Intrinsic size of the control registered at `id` under
    /// `proposal`, or `nil` to measure its child instead.
    public var controlSize: (_ id: NodeID, _ proposal: ProposedSize) -> Size?
    /// Intrinsic size of a control from its registered
    /// ``ControlDescriptor`` under `proposal`, or `nil` to fall back to
    /// ``controlSize``. `FrameHost` consults it for every node that
    /// registered a descriptor in the current build.
    public var descriptorSize: (_ descriptor: ControlDescriptor, _ proposal: ProposedSize) -> Size?

    /// Creates a metrics value from its measurements. `descriptorSize`
    /// defaults to reporting no size, so every control falls back to
    /// `controlSize`.
    public init(
        textSize: @escaping (_ text: String, _ style: TextStyle, _ width: Int?) -> Size,
        units: @escaping (_ cells: Int, _ axis: Axis) -> Int,
        dividerThickness: Int,
        controlSize: @escaping (_ id: NodeID, _ proposal: ProposedSize) -> Size?,
        descriptorSize: @escaping (_ descriptor: ControlDescriptor, _ proposal: ProposedSize) -> Size? = { _, _ in nil }
    ) {
        self.textSize = textSize
        self.units = units
        self.dividerThickness = dividerThickness
        self.controlSize = controlSize
        self.descriptorSize = descriptorSize
    }

    /// Today's cell measurements: `TextLayout.size`, an identity unit
    /// conversion, a one-cell divider, and no control sizes from either an
    /// identity or a descriptor (every interactive node measures its child). Every layout produced with
    /// `.cell` is byte-identical to layout before `LayoutMetrics` existed
    /// — the parity oracle for that claim is the existing layout, P1
    /// layout, FrameHost, DrawList, WASM, and MLIR test suites.
    public static var cell: LayoutMetrics {
        LayoutMetrics(
            textSize: { text, _, width in TextLayout.size(of: text, width: width) },
            units: { cells, _ in cells },
            dividerThickness: 1,
            controlSize: { _, _ in nil }
        )
    }
}
