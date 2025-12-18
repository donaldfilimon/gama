import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Apple platform input event handling
public class AppleInput {
    public enum EventType {
        case keyDown
        case keyUp
        case mouseDown
        case mouseUp
        case mouseMoved
        case mouseDragged
        case scrollWheel
        case touchBegan
        case touchMoved
        case touchEnded
        case touchCancelled
        case gesture
    }

    public struct KeyEvent {
        public let keyCode: UInt16
        public let characters: String?
        public let charactersIgnoringModifiers: String?
        public let modifierFlags: ModifierFlags
        public let isRepeat: Bool

        public init(keyCode: UInt16, characters: String?, charactersIgnoringModifiers: String?, modifierFlags: ModifierFlags, isRepeat: Bool) {
            self.keyCode = keyCode
            self.characters = characters
            self.charactersIgnoringModifiers = charactersIgnoringModifiers
            self.modifierFlags = modifierFlags
            self.isRepeat = isRepeat
        }
    }

    public struct MouseEvent {
        public let location: Point
        public let buttonNumber: Int
        public let clickCount: Int
        public let modifierFlags: ModifierFlags
        public let deltaX: CGFloat
        public let deltaY: CGFloat

        public init(location: Point, buttonNumber: Int, clickCount: Int, modifierFlags: ModifierFlags, deltaX: CGFloat = 0, deltaY: CGFloat = 0) {
            self.location = location
            self.buttonNumber = buttonNumber
            self.clickCount = clickCount
            self.modifierFlags = modifierFlags
            self.deltaX = deltaX
            self.deltaY = deltaY
        }
    }

    public struct TouchEvent {
        public let touches: [Touch]
        public let phase: TouchPhase

        public init(touches: [Touch], phase: TouchPhase) {
            self.touches = touches
            self.phase = phase
        }
    }

    public struct Touch {
        public let location: Point
        public let previousLocation: Point?
        public let phase: TouchPhase
        public let tapCount: Int

        public init(location: Point, previousLocation: Point?, phase: TouchPhase, tapCount: Int) {
            self.location = location
            self.previousLocation = previousLocation
            self.phase = phase
            self.tapCount = tapCount
        }
    }

    public enum TouchPhase {
        case began
        case moved
        case stationary
        case ended
        case cancelled
    }

    public struct ModifierFlags: OptionSet {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let capsLock = ModifierFlags(rawValue: 1 << 0)
        public static let shift = ModifierFlags(rawValue: 1 << 1)
        public static let control = ModifierFlags(rawValue: 1 << 2)
        public static let option = ModifierFlags(rawValue: 1 << 3)
        public static let command = ModifierFlags(rawValue: 1 << 4)
        public static let numericPad = ModifierFlags(rawValue: 1 << 5)
        public static let help = ModifierFlags(rawValue: 1 << 6)
        public static let function = ModifierFlags(rawValue: 1 << 7)
    }

    public struct ScrollEvent {
        public let location: Point
        public let deltaX: CGFloat
        public let deltaY: CGFloat
        public let deltaZ: CGFloat
        public let modifierFlags: ModifierFlags

        public init(location: Point, deltaX: CGFloat, deltaY: CGFloat, deltaZ: CGFloat, modifierFlags: ModifierFlags) {
            self.location = location
            self.deltaX = deltaX
            self.deltaY = deltaY
            self.deltaZ = deltaZ
            self.modifierFlags = modifierFlags
        }
    }

    /// Convert NSEvent to AppleInput events (macOS)
    #if os(macOS)
    public static func convertEvent(_ nsEvent: NSEvent) -> (type: EventType, event: Any)? {
        switch nsEvent.type {
        case .keyDown:
            let keyEvent = KeyEvent(
                keyCode: nsEvent.keyCode,
                characters: nsEvent.characters,
                charactersIgnoringModifiers: nsEvent.charactersIgnoringModifiers,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags),
                isRepeat: nsEvent.isARepeat
            )
            return (.keyDown, keyEvent)

        case .keyUp:
            let keyEvent = KeyEvent(
                keyCode: nsEvent.keyCode,
                characters: nsEvent.characters,
                charactersIgnoringModifiers: nsEvent.charactersIgnoringModifiers,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags),
                isRepeat: false
            )
            return (.keyUp, keyEvent)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let mouseEvent = MouseEvent(
                location: Point(x: Int32(nsEvent.locationInWindow.x), y: Int32(nsEvent.locationInWindow.y)),
                buttonNumber: nsEvent.buttonNumber,
                clickCount: nsEvent.clickCount,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags)
            )
            return (.mouseDown, mouseEvent)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let mouseEvent = MouseEvent(
                location: Point(x: Int32(nsEvent.locationInWindow.x), y: Int32(nsEvent.locationInWindow.y)),
                buttonNumber: nsEvent.buttonNumber,
                clickCount: nsEvent.clickCount,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags)
            )
            return (.mouseUp, mouseEvent)

        case .mouseMoved:
            let mouseEvent = MouseEvent(
                location: Point(x: Int32(nsEvent.locationInWindow.x), y: Int32(nsEvent.locationInWindow.y)),
                buttonNumber: nsEvent.buttonNumber,
                clickCount: nsEvent.clickCount,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags),
                deltaX: nsEvent.deltaX,
                deltaY: nsEvent.deltaY
            )
            return (.mouseMoved, mouseEvent)

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let mouseEvent = MouseEvent(
                location: Point(x: Int32(nsEvent.locationInWindow.x), y: Int32(nsEvent.locationInWindow.y)),
                buttonNumber: nsEvent.buttonNumber,
                clickCount: nsEvent.clickCount,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags),
                deltaX: nsEvent.deltaX,
                deltaY: nsEvent.deltaY
            )
            return (.mouseDragged, mouseEvent)

        case .scrollWheel:
            let scrollEvent = ScrollEvent(
                location: Point(x: Int32(nsEvent.locationInWindow.x), y: Int32(nsEvent.locationInWindow.y)),
                deltaX: nsEvent.scrollingDeltaX,
                deltaY: nsEvent.scrollingDeltaY,
                deltaZ: nsEvent.scrollingDeltaZ,
                modifierFlags: convertModifierFlags(nsEvent.modifierFlags)
            )
            return (.scrollWheel, scrollEvent)

        default:
            return nil
        }
    }

    private static func convertModifierFlags(_ nsFlags: NSEvent.ModifierFlags) -> ModifierFlags {
        var flags = ModifierFlags()

        if nsFlags.contains(.capsLock) { flags.insert(.capsLock) }
        if nsFlags.contains(.shift) { flags.insert(.shift) }
        if nsFlags.contains(.control) { flags.insert(.control) }
        if nsFlags.contains(.option) { flags.insert(.option) }
        if nsFlags.contains(.command) { flags.insert(.command) }
        if nsFlags.contains(.numericPad) { flags.insert(.numericPad) }
        if nsFlags.contains(.help) { flags.insert(.help) }
        if nsFlags.contains(.function) { flags.insert(.function) }

        return flags
    }
    #endif

    /// Convert UIEvent to AppleInput events (iOS/tvOS)
    #if os(iOS) || os(tvOS)
    public static func convertEvent(_ uiEvent: UIEvent, touches: Set<UITouch>? = nil) -> (type: EventType, event: Any)? {
        if let touches = touches ?? uiEvent.touches(for: nil) {
            return convertTouches(touches)
        }

        // Handle other UIEvent types if needed
        return nil
    }

    private static func convertTouches(_ uiTouches: Set<UITouch>) -> (type: EventType, event: Any)? {
        let touches = uiTouches.map { uiTouch -> Touch in
            let location = uiTouch.location(in: uiTouch.window)
            let previousLocation = uiTouch.previousLocation(in: uiTouch.window)

            let phase: TouchPhase
            switch uiTouch.phase {
            case .began: phase = .began
            case .moved: phase = .moved
            case .stationary: phase = .stationary
            case .ended: phase = .ended
            case .cancelled: phase = .cancelled
            @unknown default: phase = .cancelled
            }

            return Touch(
                location: Point(x: Int32(location.x), y: Int32(location.y)),
                previousLocation: Point(x: Int32(previousLocation.x), y: Int32(previousLocation.y)),
                phase: phase,
                tapCount: uiTouch.tapCount
            )
        }

        let eventType: EventType
        if let firstTouch = touches.first {
            switch firstTouch.phase {
            case .began: eventType = .touchBegan
            case .moved: eventType = .touchMoved
            case .ended: eventType = .touchEnded
            case .cancelled: eventType = .touchCancelled
            case .stationary: return nil // Don't create events for stationary touches
            }
        } else {
            return nil
        }

        let touchEvent = TouchEvent(touches: touches, phase: touches.first?.phase ?? .cancelled)
        return (eventType, touchEvent)
    }
    #endif

    /// Get current mouse location (macOS)
    #if os(macOS)
    public static func currentMouseLocation() -> Point {
        let location = NSEvent.mouseLocation
        return Point(x: Int32(location.x), y: Int32(location.y))
    }
    #endif

    /// Check if a modifier key is pressed (macOS)
    #if os(macOS)
    public static func isModifierPressed(_ modifier: ModifierFlags) -> Bool {
        let currentFlags = convertModifierFlags(NSEvent.modifierFlags)
        return currentFlags.contains(modifier)
    }
    #endif
}

/// Input event handler protocol
public protocol AppleInputDelegate: AnyObject {
    func handleKeyEvent(_ event: AppleInput.KeyEvent, type: AppleInput.EventType)
    func handleMouseEvent(_ event: AppleInput.MouseEvent, type: AppleInput.EventType)
    func handleTouchEvent(_ event: AppleInput.TouchEvent, type: AppleInput.EventType)
    func handleScrollEvent(_ event: AppleInput.ScrollEvent)
}

/// Default implementations for optional methods
public extension AppleInputDelegate {
    func handleKeyEvent(_ event: AppleInput.KeyEvent, type: AppleInput.EventType) {}
    func handleMouseEvent(_ event: AppleInput.MouseEvent, type: AppleInput.EventType) {}
    func handleTouchEvent(_ event: AppleInput.TouchEvent, type: AppleInput.EventType) {}
    func handleScrollEvent(_ event: AppleInput.ScrollEvent) {}
}