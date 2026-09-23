//  NativeRegion.swift — GamaCore
//  A laid-out region an opting-in presentation host may fill with an
//  application-owned view (ADR 0016). Every backend paints the fallback;
//  the region is an ordinary interactive node, registered with the host the
//  way Button registers its action.

/// Application-chosen identity for a native region. Equal tokens name the
/// same region; a host attaches views by this identity.
public struct NativeRegionID: Hashable, Sendable {
    /// Application-supplied token.
    public var rawValue: String

    /// Creates an identity from `rawValue`.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Reserves a laid-out, focusable region that a presentation host may fill
/// with an application-owned platform view.
///
/// Compiles to `RenderNode.interactive` around `fallback`, stretched to fill
/// the space the region is given, so every backend lays it out, focuses it,
/// hit-tests it, and paints the fallback. A host that attaches a view to
/// ``NativeRegionID`` shows that view instead, inside the region only.
public struct NativeRegion<Fallback: View>: View {
    /// A primitive: compiles directly through ``render(in:)``.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// The identity a host attaches a view to.
    public var id: NativeRegionID
    /// Whether the region takes keyboard focus; a disabled environment
    /// always removes it from focus order.
    public var focusable: Bool
    /// Painted on every backend, and wherever no view is attached.
    public var fallback: Fallback

    /// Creates a region identified by `id` with a portable `fallback`.
    public init(_ id: NativeRegionID, focusable: Bool = true, @ViewBuilder fallback: () -> Fallback) {
        self.id = id
        self.focusable = focusable
        self.fallback = fallback()
    }

    /// Registers the region with the owning host and compiles to a
    /// focusable `.interactive` node around the stretched fallback.
    public func render(in context: BuildContext) -> RenderNode {
        context.registerNativeRegion(context.id, id)
        return .interactive(
            id: context.id,
            focusable: focusable && context.environment.isEnabled,
            child: fallback.frame(maxWidth: .max, maxHeight: .max).render(in: context.child(0))
        )
    }
}
