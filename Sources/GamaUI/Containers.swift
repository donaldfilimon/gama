// Containers.swift — Layout containers (VStack, HStack, ZStack)
// Part of GamaUI

// MARK: - VStack

/// A view that arranges its children in a vertical line.
public struct VStack<Content: View>: View, Sendable {
    public typealias Body = Never

    /// The spacing between children, or `nil` for default spacing.
    public let spacing: Double?

    /// The horizontal alignment of children.
    public let alignment: HorizontalAlignment

    /// The content of the stack.
    public let content: Content

    /// Creates a vertical stack with the given spacing and content.
    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("VStack.body should never be called")
    }
}

// MARK: - HStack

/// A view that arranges its children in a horizontal line.
public struct HStack<Content: View>: View, Sendable {
    public typealias Body = Never

    /// The spacing between children, or `nil` for default spacing.
    public let spacing: Double?

    /// The vertical alignment of children.
    public let alignment: VerticalAlignment

    /// The content of the stack.
    public let content: Content

    /// Creates a horizontal stack with the given spacing and content.
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("HStack.body should never be called")
    }
}

// MARK: - ZStack

/// A view that overlays its children, aligning them on both axes.
public struct ZStack<Content: View>: View, Sendable {
    public typealias Body = Never

    /// The alignment of children within the stack.
    public let alignment: Alignment

    /// The content of the stack.
    public let content: Content

    /// Creates a z-axis stack with the given alignment and content.
    public init(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("ZStack.body should never be called")
    }
}
