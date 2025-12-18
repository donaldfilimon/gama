import Foundation

/// Platform-agnostic window protocol
public protocol WindowProtocol {
    /// Window title
    var title: String { get set }

    /// Window position (top-left corner)
    var position: Point { get set }

    /// Window size
    var size: Size { get set }

    /// Window rectangle (position + size)
    var frame: Rectangle { get set }

    /// Client area rectangle (area inside window borders)
    var clientRect: Rectangle { get }

    /// Check if window is visible
    var isVisible: Bool { get }

    /// Check if window is valid
    var isValid: Bool { get }

    /// Show the window
    func show()

    /// Hide the window
    func hide()

    /// Minimize the window
    func minimize()

    /// Maximize the window
    func maximize()

    /// Restore window to normal size
    func restore()

    /// Close the window
    func close()

    /// Update/redraw the window
    func update()

    /// Set focus to this window
    func focus()

    /// Bring window to front
    func bringToFront()

    /// Send window to back
    func sendToBack()

    /// Set window delegate
    func setDelegate(_ delegate: WindowDelegate?)

    /// Get window delegate
    func getDelegate() -> WindowDelegate?
}

/// Window delegate protocol
public protocol WindowDelegate: AnyObject {
    /// Called when window is about to close
    /// Return false to prevent closing
    func windowWillClose(_ window: WindowProtocol) -> Bool

    /// Called when window has closed
    func windowDidClose(_ window: WindowProtocol)

    /// Called when window is about to be destroyed
    func windowWillDestroy(_ window: WindowProtocol)

    /// Called when window is resized
    func windowDidResize(_ window: WindowProtocol, size: Size)

    /// Called when window is moved
    func windowDidMove(_ window: WindowProtocol, position: Point)

    /// Called when window gains focus
    func windowDidActivate(_ window: WindowProtocol)

    /// Called when window loses focus
    func windowDidDeactivate(_ window: WindowProtocol)

    /// Called when window needs painting
    func windowWillPaint(_ window: WindowProtocol)
}

/// Default implementations for WindowDelegate
public extension WindowDelegate {
    func windowWillClose(_ window: WindowProtocol) -> Bool { return true }
    func windowDidClose(_ window: WindowProtocol) {}
    func windowWillDestroy(_ window: WindowProtocol) {}
    func windowDidResize(_ window: WindowProtocol, size: Size) {}
    func windowDidMove(_ window: WindowProtocol, position: Point) {}
    func windowDidActivate(_ window: WindowProtocol) {}
    func windowDidDeactivate(_ window: WindowProtocol) {}
    func windowWillPaint(_ window: WindowProtocol) {}
}