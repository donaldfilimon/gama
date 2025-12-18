import Foundation

/// Platform-agnostic Window class that uses platform-specific implementations
public class Window: WindowProtocol {
    internal let platformWindow: WindowProtocol

    public init(platformWindow: WindowProtocol) {
        self.platformWindow = platformWindow
    }

    /// Convenience initializer using the factory
    public convenience init(
        title: String,
        position: Point? = nil,
        size: Size? = nil,
        style: WindowStyleOptions = .overlappedWindow,
        parent: Window? = nil
    ) throws {
        let window = try WindowFactory.createWindow(
            title: title,
            position: position,
            size: size,
            style: style,
            parent: parent?.platformWindow
        )
        self.init(platformWindow: window)
    }

    /// Initialize from existing native handle
    public convenience init?(handle: WindowHandle) {
        guard let window = WindowFactory.createWindowFromHandle(handle) else {
            return nil
        }
        self.init(platformWindow: window)
    }

    // MARK: - WindowProtocol Implementation

    public var title: String {
        get { platformWindow.title }
        set { platformWindow.title = newValue }
    }

    public var position: Point {
        get { platformWindow.position }
        set { platformWindow.position = newValue }
    }

    public var size: Size {
        get { platformWindow.size }
        set { platformWindow.size = newValue }
    }

    public var frame: Rectangle {
        get { platformWindow.frame }
        set { platformWindow.frame = newValue }
    }

    public var clientRect: Rectangle {
        platformWindow.clientRect
    }

    public var isVisible: Bool {
        platformWindow.isVisible
    }

    public var isValid: Bool {
        platformWindow.isValid
    }

    public func show() {
        platformWindow.show()
    }

    public func hide() {
        platformWindow.hide()
    }

    public func minimize() {
        platformWindow.minimize()
    }

    public func maximize() {
        platformWindow.maximize()
    }

    public func restore() {
        platformWindow.restore()
    }

    public func close() {
        platformWindow.close()
    }

    public func update() {
        platformWindow.update()
    }

    public func focus() {
        platformWindow.focus()
    }

    public func bringToFront() {
        platformWindow.bringToFront()
    }

    public func sendToBack() {
        platformWindow.sendToBack()
    }

    public func setDelegate(_ delegate: WindowDelegate?) {
        platformWindow.setDelegate(delegate)
    }

    public func getDelegate() -> WindowDelegate? {
        platformWindow.getDelegate()
    }
    
    #if canImport(WinSDK)
    /// Access Windows-specific handle (Windows only)
    public var hwnd: HWND? {
        return (platformWindow as? WindowsWindow)?.hwnd
    }
    #endif
}