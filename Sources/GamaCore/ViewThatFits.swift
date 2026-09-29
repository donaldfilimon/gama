//  ViewThatFits.swift — GamaCore
//  Responsive layout decided at build time: `WidthClass` buckets the
//  surface width, and `ViewThatFits` renders the first of several
//  candidates whose ideal size fits the surface. Both read
//  `EnvironmentValues.surfaceSize`, which the owning `FrameHost` sets
//  before each build, so both share its limit: they see the whole surface,
//  not the frame layout later gives a subtree.

/// A coarse bucket of the surface width, for layouts that switch shape
/// rather than stretch. Read it as ``EnvironmentValues/widthClass``.
public enum WidthClass: Hashable, Sendable {
    /// Fewer than ``regularMinimumWidth`` columns: one column of content.
    case compact
    /// From ``regularMinimumWidth`` up to, but not including,
    /// ``wideMinimumWidth`` columns: the classic 80-column terminal.
    case regular
    /// ``wideMinimumWidth`` columns or more: room for side-by-side panes.
    case wide

    /// The narrowest surface, in columns, that is ``regular``.
    public static let regularMinimumWidth = 60
    /// The narrowest surface, in columns, that is ``wide``.
    public static let wideMinimumWidth = 120

    /// The class of a surface `width` columns wide.
    public init(width: Int) {
        if width >= Self.wideMinimumWidth {
            self = .wide
        } else if width >= Self.regularMinimumWidth {
            self = .regular
        } else {
            self = .compact
        }
    }
}

extension EnvironmentValues {
    /// The ``WidthClass`` of ``surfaceSize``'s width, or `nil` for
    /// host-less rendering, where no surface exists.
    ///
    /// Like ``surfaceSize`` it describes the whole surface, not the space a
    /// subtree is later given.
    public var widthClass: WidthClass? {
        surfaceSize.map { WidthClass(width: $0.width) }
    }
}

/// An ordered list of alternative views that ``ViewThatFits`` chooses
/// from. A ``ViewBuilder`` closure with two or more statements produces a
/// ``TupleView``, which conforms; nothing else needs to.
public protocol ViewCandidates {
    /// How many candidates the list holds.
    var candidateCount: Int { get }
    /// Compiles the candidate at `index` (zero-based, in declaration order)
    /// under `context`. An out-of-range index renders `.empty`.
    func renderCandidate(_ index: Int, in context: BuildContext) -> RenderNode
}

extension TupleView: ViewCandidates {
    /// The number of views in the tuple.
    public var candidateCount: Int {
        var count = 0
        for _ in repeat each content { count += 1 }
        return count
    }

    /// Compiles only the element at `index`, under the same positional
    /// child identity ``render(in:)`` would give it.
    public func renderCandidate(_ index: Int, in context: BuildContext) -> RenderNode {
        var result = RenderNode.empty
        var position = 0
        for view in repeat each content {
            if position == index {
                result = view.render(in: context.child(position))
            }
            position += 1
        }
        return result
    }
}

/// Renders the first of its candidate views whose ideal size fits the
/// surface, falling back to the last candidate when none fits.
///
/// ```swift
/// ViewThatFits {
///     HStack { Sidebar(); Detail() }   // tried first
///     Detail()                         // the fallback
/// }
/// ```
///
/// Each candidate is built and measured with ``LayoutEngine/measure(_:proposal:)``
/// under an unconstrained proposal, so it reports its ideal size; it fits
/// when that size is no larger than ``EnvironmentValues/surfaceSize`` on
/// both axes. Candidates are measured in order and measuring stops at the
/// first fit. Probing builds a candidate with a context whose
/// registrations are discarded, so only the chosen candidate registers
/// actions, key handlers and native regions; it then renders under its own
/// positional identity, so each candidate keeps distinct state and focus.
///
/// **State.** Every candidate is built on every frame, including those
/// after the first fit, which are built but not measured. The probe keeps
/// the host's `@Reactive` store, so each candidate's state stays live
/// whether or not it is the one shown: a counter in one layout survives a
/// switch to another and back, in either direction, and a candidate is
/// measured with its live state, so one that its own state pushed out of
/// fitting stays out rather than being reset and chosen again. This is a
/// deliberate exception to ADR 0011's rule that a subtree which stops
/// rendering releases its state: the candidates are declared members of
/// the tree, shown one at a time. The cost is one probe build of every
/// candidate per frame, on top of the chosen candidate's real build.
///
/// **Limit.** The choice is made while building, before layout, so it fits
/// the whole surface, not the frame a parent stack later gives this view.
/// Nested inside a split, it still measures against the full surface.
/// Without a surface (host-less rendering) the first candidate renders.
public struct ViewThatFits<Candidates: ViewCandidates>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The candidates, in preference order.
    public let candidates: Candidates

    /// Creates a view that renders the first of `candidates` that fits,
    /// in the order they are written.
    public init(@ViewBuilder _ candidates: () -> Candidates) {
        self.candidates = candidates()
    }

    /// Chooses a candidate against the surface, then renders only that one.
    public func render(in context: BuildContext) -> RenderNode {
        candidates.renderCandidate(chosenIndex(in: context), in: context)
    }

    /// The index of the first candidate whose ideal size fits the surface,
    /// the last index when none does, or 0 without a surface.
    private func chosenIndex(in context: BuildContext) -> Int {
        let count = candidates.candidateCount
        guard let surface = context.environment.surfaceSize, count > 1 else { return 0 }
        var probe = context
        probe.registerAction = { _, _ in }
        probe.registerKeyHandler = { _, _ in }
        probe.registerNamedAction = { _, _, _ in }
        probe.registerNativeRegion = { _, _ in }
        // Build every candidate, so each one's `@Reactive` slots are
        // resolved and kept live by the host's sweep; measure only until
        // the first fit. The last candidate is the fallback and is never
        // measured.
        var chosen: Int? = nil
        for index in 0..<count {
            let node = candidates.renderCandidate(index, in: probe)
            guard chosen == nil, index < count - 1 else { continue }
            let ideal = LayoutEngine.measure(node, proposal: .unspecified)
            if ideal.width <= surface.width && ideal.height <= surface.height {
                chosen = index
            }
        }
        return chosen ?? count - 1
    }
}
