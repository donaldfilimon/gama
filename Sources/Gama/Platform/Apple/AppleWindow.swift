import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Apple platform window implementation
#if os(macOS) || os(iOS) || os(tvOS)
public class AppleWindow: WindowProtocol {
    #if os(macOS)
    private let nsWindow: NSWindow
    private var windowDelegate: AppleWindowDelegate?
    #endif

    #if os(iOS) || os(tvOS)
    private let uiWindow: UIWindow
    private var windowDelegate: AppleWindowDelegate?
    #endif

    public var title: String {
        get {
            #if os(macOS)
            return nsWindow.title
            #else
            return uiWindow.windowScene?.title ?? ""
            #endif
        }
        set {
            #if os(macOS)
            nsWindow.title = newValue
            #endif
        }
    }

    public var position: Point {
        get {
            #if os(macOS)
            let frame = nsWindow.frame
            return Point(x: Int32(frame.origin.x), y: Int32(frame.origin.y))
            #else
            let frame = uiWindow.frame
            return Point(x: Int32(frame.origin.x), y: Int32(frame.origin.y))
            #endif
        }
        set {
            #if os(macOS)
            let currentFrame = nsWindow.frame
            let newFrame = NSRect(x: CGFloat(newValue.x),
                                y: CGFloat(newValue.y),
                                width: currentFrame.width,
                                height: currentFrame.height)
            nsWindow.setFrame(newFrame, display: true)
            #endif
        }
    }

    public var size: Size {
        get {
            #if os(macOS)
            let frame = nsWindow.frame
            return Size(width: Int32(frame.width), height: Int32(frame.height))
            #else
            let frame = uiWindow.frame
            return Size(width: Int32(frame.width), height: Int32(frame.height))
            #endif
        }
        set {
            #if os(macOS)
            let currentFrame = nsWindow.frame
            let newFrame = NSRect(x: currentFrame.origin.x,
                                y: currentFrame.origin.y,
                                width: CGFloat(newValue.width),
                                height: CGFloat(newValue.height))
            nsWindow.setFrame(newFrame, display: true)
            #else
            uiWindow.frame.size = CGSize(width: CGFloat(newValue.width),
                                       height: CGFloat(newValue.height))
            #endif
        }
    }

    public var frame: Rectangle {
        get {
            #if os(macOS)
            let nsFrame = nsWindow.frame
            return Rectangle(left: Int32(nsFrame.origin.x),
                           top: Int32(nsFrame.origin.y),
                           right: Int32(nsFrame.origin.x + nsFrame.width),
                           bottom: Int32(nsFrame.origin.y + nsFrame.height))
            #else
            let uiFrame = uiWindow.frame
            return Rectangle(left: Int32(uiFrame.origin.x),
                           top: Int32(uiFrame.origin.y),
                           right: Int32(uiFrame.origin.x + uiFrame.width),
                           bottom: Int32(uiFrame.origin.y + uiFrame.height))
            #endif
        }
        set {
            #if os(macOS)
            let nsFrame = NSRect(x: CGFloat(newValue.left),
                               y: CGFloat(newValue.top),
                               width: CGFloat(newValue.width),
                               height: CGFloat(newValue.height))
            nsWindow.setFrame(nsFrame, display: true)
            #else
            uiWindow.frame = CGRect(x: CGFloat(newValue.left),
                                  y: CGFloat(newValue.top),
                                  width: CGFloat(newValue.width),
                                  height: CGFloat(newValue.height))
            #endif
        }
    }

    public var clientRect: Rectangle {
        get {
            #if os(macOS)
            let contentRect = nsWindow.contentRect(forFrameRect: nsWindow.frame)
            return Rectangle(left: Int32(contentRect.origin.x),
                           top: Int32(contentRect.origin.y),
                           right: Int32(contentRect.origin.x + contentRect.width),
                           bottom: Int32(contentRect.origin.y + contentRect.height))
            #else
            let bounds = uiWindow.bounds
            return Rectangle(left: Int32(bounds.origin.x),
                           top: Int32(bounds.origin.y),
                           right: Int32(bounds.origin.x + bounds.width),
                           bottom: Int32(bounds.origin.y + bounds.height))
            #endif
        }
    }

    public var isVisible: Bool {
        #if os(macOS)
        return nsWindow.isVisible
        #else
        return !uiWindow.isHidden
        #endif
    }

    public var isValid: Bool {
        #if os(macOS)
        return nsWindow.windowNumber != -1
        #else
        return uiWindow.windowScene != nil
        #endif
    }

    #if os(macOS)
    public init(title: String, position: Point?, size: Size?, style: WindowStyleOptions, parent: AppleWindow?) {
        let width = size?.width ?? 800
        let height = size?.height ?? 600
        let x = position?.x ?? 100
        let y = position?.y ?? 100

        let frame = NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

        nsWindow = NSWindow(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)
        nsWindow.title = title

        windowDelegate = AppleWindowDelegate(appleWindow: self)
        nsWindow.delegate = windowDelegate
    }

    public convenience init(handle: WindowHandle) {
        // Convert from WindowHandle to NSWindow
        if let nsWindowHandle = handle as? NSWindow {
            self.init(nsWindow: nsWindowHandle)
        } else {
            // Fallback - create a new window
            self.init(title: "", position: nil, size: nil, style: .overlappedWindow, parent: nil)
        }
    }

    private init(nsWindow: NSWindow) {
        self.nsWindow = nsWindow
        windowDelegate = AppleWindowDelegate(appleWindow: self)
        nsWindow.delegate = windowDelegate
    }
    #endif

    #if os(iOS) || os(tvOS)
    public init(title: String, position: Point?, size: Size?, style: WindowStyleOptions, parent: AppleWindow?) {
        let width = size?.width ?? Int32(UIScreen.main.bounds.width)
        let height = size?.height ?? Int32(UIScreen.main.bounds.height)

        let frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        uiWindow = UIWindow(frame: frame)

        #if os(iOS)
        uiWindow.windowScene?.title = title
        #endif

        windowDelegate = AppleWindowDelegate(appleWindow: self)
        uiWindow.windowScene?.delegate = windowDelegate as? UIWindowSceneDelegate
    }

    public convenience init(handle: WindowHandle) {
        // Convert from WindowHandle to UIWindow
        if let uiWindowHandle = handle as? UIWindow {
            self.init(uiWindow: uiWindowHandle)
        } else {
            // Fallback - create a new window
            self.init(title: "", position: nil, size: nil, style: .overlappedWindow, parent: nil)
        }
    }

    private init(uiWindow: UIWindow) {
        self.uiWindow = uiWindow
        windowDelegate = AppleWindowDelegate(appleWindow: self)
        uiWindow.windowScene?.delegate = windowDelegate as? UIWindowSceneDelegate
    }
    #endif

    public func show() {
        #if os(macOS)
        nsWindow.makeKeyAndOrderFront(nil)
        #else
        uiWindow.makeKeyAndVisible()
        #endif
    }

    public func hide() {
        #if os(macOS)
        nsWindow.orderOut(nil)
        #else
        uiWindow.isHidden = true
        #endif
    }

    public func minimize() {
        #if os(macOS)
        nsWindow.miniaturize(nil)
        #endif
        // iOS/tvOS don't have minimize concept
    }

    public func maximize() {
        #if os(macOS)
        nsWindow.zoom(nil)
        #endif
        // iOS/tvOS don't have maximize concept
    }

    public func restore() {
        #if os(macOS)
        if nsWindow.isMiniaturized {
            nsWindow.deminiaturize(nil)
        }
        if nsWindow.isZoomed {
            nsWindow.zoom(nil)
        }
        #endif
        // iOS/tvOS don't have restore concept
    }

    public func close() {
        #if os(macOS)
        nsWindow.close()
        #else
        uiWindow.isHidden = true
        #endif
    }

    public func update() {
        #if os(macOS)
        nsWindow.display()
        #else
        uiWindow.setNeedsDisplay()
        #endif
    }

    public func focus() {
        #if os(macOS)
        nsWindow.makeKeyAndOrderFront(nil)
        #else
        uiWindow.makeKey()
        #endif
    }

    public func bringToFront() {
        #if os(macOS)
        nsWindow.orderFront(nil)
        #else
        // iOS manages window ordering differently
        #endif
    }

    public func sendToBack() {
        #if os(macOS)
        nsWindow.orderBack(nil)
        #else
        // iOS manages window ordering differently
        #endif
    }

    public func setDelegate(_ delegate: WindowDelegate?) {
        windowDelegate?.externalDelegate = delegate
    }

    public func getDelegate() -> WindowDelegate? {
        return windowDelegate?.externalDelegate
    }
}

/// Delegate class to handle Apple window events
private class AppleWindowDelegate: NSObject {
    weak var appleWindow: AppleWindow?
    weak var externalDelegate: WindowDelegate?

    init(appleWindow: AppleWindow) {
        self.appleWindow = appleWindow
    }
}

#if os(macOS)
extension AppleWindowDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        externalDelegate?.windowWillClose(appleWindow!)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        externalDelegate?.windowDidActivate(appleWindow!)
    }

    func windowDidResignKey(_ notification: Notification) {
        externalDelegate?.windowDidDeactivate(appleWindow!)
    }

    func windowDidResize(_ notification: Notification) {
        if let window = appleWindow {
            externalDelegate?.windowDidResize(window, size: window.size)
        }
    }

    func windowDidMove(_ notification: Notification) {
        if let window = appleWindow {
            externalDelegate?.windowDidMove(window, position: window.position)
        }
    }
}
#endif

#if os(iOS) || os(tvOS)
extension AppleWindowDelegate: UIWindowSceneDelegate {
    func sceneDidBecomeActive(_ scene: UIScene) {
        externalDelegate?.windowDidActivate(appleWindow!)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        externalDelegate?.windowDidDeactivate(appleWindow!)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Window became visible
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Window became hidden
    }
}
#endif
#endif