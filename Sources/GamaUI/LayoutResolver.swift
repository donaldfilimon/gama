// LayoutResolver.swift — Resolves layout behavior and children from View types
// Part of GamaUI

import Foundation

// MARK: - Layout Behavior

/// Describes how a view participates in layout.
internal enum LayoutBehavior: Sendable {
    /// A leaf view with fixed or flexible size.
    case leaf

    /// A flexible spacer that expands to fill available space.
    case spacer(minLength: Double?)

    /// A vertical stack layout.
    case vStack(spacing: Double?, alignment: HorizontalAlignment)

    /// A horizontal stack layout.
    case hStack(spacing: Double?, alignment: VerticalAlignment)

    /// A z-axis overlay layout.
    case zStack(alignment: Alignment)

    /// A view with padding applied.
    case padded(insets: EdgeInsets)

    /// A view constrained to a specific frame.
    case framed(width: Double?, height: Double?, alignment: Alignment)

    /// A view with a background (layout follows foreground).
    case background

    /// A view with foreground color (passes through to child).
    case foregroundColor

    /// A modified view (passes through to modifier body).
    case modified

    /// A type-erased view.
    case erased
}

// MARK: - Layout Resolver

/// Resolves the layout behavior and children for any `View` type.
internal enum LayoutResolver {
    /// Returns the layout behavior for a view.
    static func behavior<V: View>(for view: V) -> LayoutBehavior {
        switch view {
        case is EmptyView:
            return .leaf
        case let spacer as Spacer:
            return .spacer(minLength: spacer.minLength)
        case let vstack as any _VStackProtocol:
            return .vStack(spacing: vstack._spacing, alignment: vstack._alignment)
        case let hstack as any _HStackProtocol:
            return .hStack(spacing: hstack._spacing, alignment: hstack._alignment)
        case let zstack as any _ZStackProtocol:
            return .zStack(alignment: zstack._alignment)
        case let padded as PaddedView:
            _ = padded
            return .padded(insets: padded.insets)
        case let framed as FramedView:
            return .framed(width: framed.width, height: framed.height, alignment: framed.alignment)
        case is any _BackgroundViewProtocol:
            return .background
        case is any _ForegroundColorViewProtocol:
            return .foregroundColor
        case is AnyView:
            return .erased
        default:
            // For composite views (e.g. ModifiedView), resolve through the body
            return resolveBodyBehavior(of: view)
        }
    }

    /// Resolves layout behavior by evaluating a view's body.
    private static func resolveBodyBehavior<V: View>(of view: V) -> LayoutBehavior {
        if V.Body.self == Never.self {
            return .leaf
        }
        return behavior(for: view.body)
    }

    /// Extracts the child views from a view for layout purposes.
    static func children<V: View>(of view: V) -> [AnyView] {
        switch view {
        case let vstack as any _VStackProtocol:
            return vstack._children
        case let hstack as any _HStackProtocol:
            return hstack._children
        case let zstack as any _ZStackProtocol:
            return zstack._children
        case let padded as PaddedView:
            return [padded.content]
        case let framed as FramedView:
            return [framed.content]
        case let bg as any _BackgroundViewProtocol:
            return [bg._content]
        case let fg as any _ForegroundColorViewProtocol:
            return [fg._anyContent]
        case let erased as AnyView:
            return erased.childProvider()
        default:
            return resolveBodyChildren(of: view)
        }
    }

    /// Resolves children by evaluating a view's body.
    private static func resolveBodyChildren<V: View>(of view: V) -> [AnyView] {
        if V.Body.self == Never.self {
            return []
        }
        return children(of: view.body)
    }
}

// MARK: - Internal Protocols for Type Erasure

/// Internal protocol for type-erasing VStack.
internal protocol _VStackProtocol {
    var _spacing: Double? { get }
    var _alignment: HorizontalAlignment { get }
    var _children: [AnyView] { get }
}

/// Internal protocol for type-erasing HStack.
internal protocol _HStackProtocol {
    var _spacing: Double? { get }
    var _alignment: VerticalAlignment { get }
    var _children: [AnyView] { get }
}

/// Internal protocol for type-erasing ZStack.
internal protocol _ZStackProtocol {
    var _alignment: Alignment { get }
    var _children: [AnyView] { get }
}

/// Internal protocol for type-erasing BackgroundView.
internal protocol _BackgroundViewProtocol {
    var _content: AnyView { get }
}

/// Internal protocol for type-erasing ForegroundColorView.
internal protocol _ForegroundColorViewProtocol {
    var _anyContent: AnyView { get }
}

// MARK: - Protocol Conformances

extension VStack: _VStackProtocol {
    internal var _spacing: Double? { spacing }
    internal var _alignment: HorizontalAlignment { alignment }
    internal var _children: [AnyView] { extractChildren(from: content) }
}

extension HStack: _HStackProtocol {
    internal var _spacing: Double? { spacing }
    internal var _alignment: VerticalAlignment { alignment }
    internal var _children: [AnyView] { extractChildren(from: content) }
}

extension ZStack: _ZStackProtocol {
    internal var _alignment: Alignment { alignment }
    internal var _children: [AnyView] { extractChildren(from: content) }
}

extension BackgroundView: _BackgroundViewProtocol {
    internal var _content: AnyView { content }
}

extension ForegroundColorView: _ForegroundColorViewProtocol {
    internal var _anyContent: AnyView { AnyView(content) }
}

// MARK: - Child Extraction

/// Extracts individual child views from tuple views and other composite types.
internal func extractChildren<V: View>(from view: V) -> [AnyView] {
    switch view {
    case is EmptyView:
        return []
    case let tuple as any _TupleView2Protocol:
        return tuple._children
    case let tuple as any _TupleView3Protocol:
        return tuple._children
    case let tuple as any _TupleView4Protocol:
        return tuple._children
    case let tuple as any _TupleView5Protocol:
        return tuple._children
    default:
        return [AnyView(view)]
    }
}

// MARK: - Tuple View Protocols

internal protocol _TupleView2Protocol {
    var _children: [AnyView] { get }
}

internal protocol _TupleView3Protocol {
    var _children: [AnyView] { get }
}

internal protocol _TupleView4Protocol {
    var _children: [AnyView] { get }
}

internal protocol _TupleView5Protocol {
    var _children: [AnyView] { get }
}

extension TupleView2: _TupleView2Protocol {
    internal var _children: [AnyView] { [AnyView(v0), AnyView(v1)] }
}

extension TupleView3: _TupleView3Protocol {
    internal var _children: [AnyView] { [AnyView(v0), AnyView(v1), AnyView(v2)] }
}

extension TupleView4: _TupleView4Protocol {
    internal var _children: [AnyView] { [AnyView(v0), AnyView(v1), AnyView(v2), AnyView(v3)] }
}

extension TupleView5: _TupleView5Protocol {
    internal var _children: [AnyView] { [AnyView(v0), AnyView(v1), AnyView(v2), AnyView(v3), AnyView(v4)] }
}
