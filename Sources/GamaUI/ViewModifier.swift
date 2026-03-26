// ViewModifier.swift — ViewModifier protocol and built-in modifiers
// Part of GamaUI

import Foundation

// MARK: - ViewModifier Protocol

/// A modifier that transforms a view's appearance or layout.
public protocol ViewModifier: Sendable {
    /// The type of view returned after applying the modifier.
    associatedtype ModifiedBody: View

    /// Applies the modifier to the given content.
    func body(content: Content) -> ModifiedBody

    /// A wrapper around the view being modified.
    typealias Content = ModifierContent
}

/// The content placeholder passed to a `ViewModifier`.
public struct ModifierContent: View, Sendable {
    public typealias Body = Never

    /// The type-erased original view.
    internal let wrapped: AnyView

    /// Creates modifier content wrapping the given view.
    internal init<V: View>(_ view: V) {
        self.wrapped = AnyView(view)
    }

    public var body: Never {
        fatalError("ModifierContent.body should never be called")
    }
}

// MARK: - ModifiedView

/// A view that has been transformed by a `ViewModifier`.
public struct ModifiedView<Content: View, Modifier: ViewModifier>: View, Sendable {
    public typealias Body = Modifier.ModifiedBody

    /// The original view.
    public let content: Content

    /// The modifier applied to the view.
    public let modifier: Modifier

    /// The modified body.
    public var body: Modifier.ModifiedBody {
        modifier.body(content: ModifierContent(content))
    }
}

// MARK: - View Extension

extension View {
    /// Applies a modifier to this view.
    public func modifier<M: ViewModifier>(_ modifier: M) -> ModifiedView<Self, M> {
        ModifiedView(content: self, modifier: modifier)
    }
}

// MARK: - Padding Modifier

/// A modifier that adds padding around a view.
public struct PaddingModifier: ViewModifier, Sendable {
    /// The edge insets to apply.
    public let insets: EdgeInsets

    /// Creates a padding modifier with the given insets.
    public init(_ insets: EdgeInsets) {
        self.insets = insets
    }

    public func body(content: Content) -> PaddedView {
        PaddedView(content: AnyView(content), insets: insets)
    }
}

/// A view with padding applied.
public struct PaddedView: View, Sendable {
    public typealias Body = Never

    /// The padded content.
    public let content: AnyView

    /// The padding insets.
    public let insets: EdgeInsets

    public var body: Never {
        fatalError("PaddedView.body should never be called")
    }
}

// MARK: - Frame Modifier

/// A modifier that constrains a view to a specific size.
public struct FrameModifier: ViewModifier, Sendable {
    /// The fixed width, or `nil` for unconstrained.
    public let width: Double?

    /// The fixed height, or `nil` for unconstrained.
    public let height: Double?

    /// The alignment of the content within the frame.
    public let alignment: Alignment

    /// Creates a frame modifier with optional width and height.
    public init(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    public func body(content: Content) -> FramedView {
        FramedView(content: AnyView(content), width: width, height: height, alignment: alignment)
    }
}

/// A view constrained to a specific frame.
public struct FramedView: View, Sendable {
    public typealias Body = Never

    /// The framed content.
    public let content: AnyView

    /// The constrained width.
    public let width: Double?

    /// The constrained height.
    public let height: Double?

    /// The alignment within the frame.
    public let alignment: Alignment

    public var body: Never {
        fatalError("FramedView.body should never be called")
    }
}

// MARK: - Background Modifier

/// A modifier that places a view behind the content.
public struct BackgroundModifier<Background: View>: ViewModifier, Sendable {
    /// The background view.
    public let background: Background

    /// Creates a background modifier with the given view.
    public init(_ background: Background) {
        self.background = background
    }

    public func body(content: Content) -> BackgroundView<Background> {
        BackgroundView(content: AnyView(content), background: background)
    }
}

/// A view with a background view.
public struct BackgroundView<Background: View>: View, Sendable {
    public typealias Body = Never

    /// The foreground content.
    public let content: AnyView

    /// The background view.
    public let background: Background

    public var body: Never {
        fatalError("BackgroundView.body should never be called")
    }
}

// MARK: - View Modifier Convenience Extensions

extension View {
    /// Adds uniform padding around the view.
    public func padding(_ value: Double = 8) -> ModifiedView<Self, PaddingModifier> {
        modifier(PaddingModifier(EdgeInsets(value)))
    }

    /// Adds padding with specific edge insets.
    public func padding(_ insets: EdgeInsets) -> ModifiedView<Self, PaddingModifier> {
        modifier(PaddingModifier(insets))
    }

    /// Constrains the view to a specific frame size.
    public func frame(
        width: Double? = nil,
        height: Double? = nil,
        alignment: Alignment = .center
    ) -> ModifiedView<Self, FrameModifier> {
        modifier(FrameModifier(width: width, height: height, alignment: alignment))
    }

    /// Places a background view behind this view.
    public func background<B: View>(_ background: B) -> ModifiedView<Self, BackgroundModifier<B>> {
        modifier(BackgroundModifier(background))
    }

    /// Sets the foreground color of a text view.
    public func foregroundColor(_ color: Color) -> some View {
        ForegroundColorView(content: self, color: color)
    }
}

// MARK: - ForegroundColor View

/// A view with a foreground color applied.
public struct ForegroundColorView<Content: View>: View, Sendable {
    public typealias Body = Never

    /// The content view.
    public let content: Content

    /// The foreground color.
    public let color: Color

    public var body: Never {
        fatalError("ForegroundColorView.body should never be called")
    }
}
