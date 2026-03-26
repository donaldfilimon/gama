// LeafViews.swift — Built-in leaf views (Text, Rectangle, Circle, Spacer, Image)
// Part of GamaUI

// MARK: - EmptyView

/// A view that displays nothing and takes up no space.
public struct EmptyView: View, Sendable {
    public typealias Body = Never

    /// Creates an empty view.
    public init() {}

    public var body: Never {
        fatalError("EmptyView is a leaf view")
    }
}

// MARK: - Text

/// A view that displays a string of text.
public struct Text: View, Sendable {
    public typealias Body = Never

    /// The string content to display.
    public let content: String

    /// The font for rendering the text.
    public var font: Font?

    /// The text color.
    public var foregroundColor: Color?

    /// Creates a text view with the given string.
    public init(_ content: String) {
        self.content = content
    }

    public var body: Never {
        fatalError("Text.body should never be called")
    }
}

// MARK: - Rectangle

/// A rectangular shape view.
public struct Rectangle: View, Sendable {
    public typealias Body = Never

    /// Creates a rectangle view.
    public init() {}

    public var body: Never {
        fatalError("Rectangle.body should never be called")
    }
}

// MARK: - Circle

/// A circular shape view.
public struct Circle: View, Sendable {
    public typealias Body = Never

    /// Creates a circle view.
    public init() {}

    public var body: Never {
        fatalError("Circle.body should never be called")
    }
}

// MARK: - Spacer

/// A flexible space that expands along the major axis of its parent layout.
public struct Spacer: View, Sendable {
    public typealias Body = Never

    /// The minimum length of the spacer, or `nil` for the default minimum.
    public let minLength: Double?

    /// Creates a spacer with an optional minimum length.
    public init(minLength: Double? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer.body should never be called")
    }
}

// MARK: - Button

/// A control that initiates an action when tapped.
public struct Button<Label: View>: View, Sendable {
    public typealias Body = Never

    /// The view displayed as the button's label.
    public let label: Label

    /// The action to perform when the button is activated.
    public let action: @Sendable () -> Void

    /// Creates a button with a label view and action closure.
    public init(action: @escaping @Sendable () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public var body: Never {
        fatalError("Button.body should never be called")
    }
}

extension Button where Label == Text {
    /// Creates a button with a text label and action closure.
    public init(_ title: String, action: @escaping @Sendable () -> Void) {
        self.action = action
        self.label = Text(title)
    }
}

// MARK: - Image

/// A placeholder view for GPU texture display.
///
/// The actual rendering is deferred to a future integration unit.
public struct Image: View, Sendable {
    public typealias Body = Never

    /// The name or identifier of the image resource.
    public let name: String

    /// Creates an image view with the given resource name.
    public init(_ name: String) {
        self.name = name
    }

    public var body: Never {
        fatalError("Image.body should never be called")
    }
}
