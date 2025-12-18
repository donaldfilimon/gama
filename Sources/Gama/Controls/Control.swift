import Foundation

/// Base protocol for all controls
public protocol Control {
    var window: Window { get }

    /// Enable or disable the control
    func setEnabled(_ enabled: Bool)

    /// Check if the control is enabled
    var isEnabled: Bool { get }

    /// Show or hide the control
    func setVisible(_ visible: Bool)

    /// Check if the control is visible
    var isVisible: Bool { get }

    /// Get or set the control text
    var text: String { get set }

    /// Get control position
    var position: Point { get set }

    /// Get control size
    var size: Size { get set }
}

/// Platform-agnostic base control class
public class BaseControl: Control {
    public let window: Window
    private let platformControl: any Control

    public init(window: Window) {
        self.window = window

        #if canImport(WinSDK)
        self.platformControl = WindowsBaseControl(window: window)
        #else
        self.platformControl = StubControl(window: window)
        #endif
    }

    /// Enable or disable the control
    public func setEnabled(_ enabled: Bool) {
        platformControl.setEnabled(enabled)
    }

    /// Check if the control is enabled
    public var isEnabled: Bool {
        return platformControl.isEnabled
    }

    /// Show or hide the control
    public func setVisible(_ visible: Bool) {
        platformControl.setVisible(visible)
    }

    /// Check if the control is visible
    public var isVisible: Bool {
        return platformControl.isVisible
    }

    /// Get or set the control text
    public var text: String {
        get { return platformControl.text }
        set { platformControl.text = newValue }
    }

    /// Get control position
    public var position: Point {
        get { return platformControl.position }
        set { platformControl.position = newValue }
    }

    /// Get control size
    public var size: Size {
        get { return platformControl.size }
        set { platformControl.size = newValue }
    }
}

/// Stub control implementation for platforms without native control support
private class StubControl: Control {
    public let window: Window

    public init(window: Window) {
        self.window = window
    }

    /// Enable or disable the control (stub)
    public func setEnabled(_ enabled: Bool) {
        print("Control.setEnabled(\(enabled)) - stub implementation")
    }

    /// Check if the control is enabled (stub)
    public var isEnabled: Bool {
        return true // Default to enabled
    }

    /// Show or hide the control (stub)
    public func setVisible(_ visible: Bool) {
        print("Control.setVisible(\(visible)) - stub implementation")
    }

    /// Check if the control is visible (stub)
    public var isVisible: Bool {
        return true // Default to visible
    }

    /// Get or set the control text (stub)
    public var text: String {
        get { return "" }
        set { print("Control.text = '\(newValue)' - stub implementation") }
    }

    /// Get control position (stub)
    public var position: Point {
        get { return Point(x: 0, y: 0) }
        set { print("Control.position = \(newValue) - stub implementation") }
    }

    /// Get control size (stub)
    public var size: Size {
        get { return Size(width: 100, height: 20) } // Default size
        set { print("Control.size = \(newValue) - stub implementation") }
    }
}