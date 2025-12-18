import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Keyboard input handling utilities
#if canImport(WinSDK)
public struct Keyboard {
    /// Check if a key is currently pressed
    public static func isKeyDown(_ virtualKey: VirtualKey) -> Bool {
        return (GetAsyncKeyState(Int32(virtualKey.rawValue)) & 0x8000) != 0
    }
    
    /// Check if a key was pressed since last call
    public static func isKeyPressed(_ virtualKey: VirtualKey) -> Bool {
        return (GetAsyncKeyState(Int32(virtualKey.rawValue)) & 0x01) != 0
    }
    
    /// Get keyboard state for all keys
    public static func getKeyboardState() -> [UInt8] {
        var state = [UInt8](repeating: 0, count: 256)
        GetKeyboardState(&state)
        return state
    }
    
    /// Check if a specific key is down from keyboard state
    public static func isKeyDownInState(_ virtualKey: VirtualKey, state: [UInt8]) -> Bool {
        guard virtualKey.rawValue < 256 else { return false }
        return (state[Int(virtualKey.rawValue)] & 0x80) != 0
    }
    
    /// Convert virtual key to character (considering keyboard layout)
    public static func virtualKeyToCharacter(_ virtualKey: VirtualKey, shift: Bool = false, capsLock: Bool = false) -> Character? {
        // Basic mapping for common keys
        switch virtualKey {
        case .space: return " "
        case .keyA: return shift || capsLock ? "A" : "a"
        case .keyB: return shift || capsLock ? "B" : "b"
        case .keyC: return shift || capsLock ? "C" : "c"
        case .keyD: return shift || capsLock ? "D" : "d"
        case .keyE: return shift || capsLock ? "E" : "e"
        case .keyF: return shift || capsLock ? "F" : "f"
        case .keyG: return shift || capsLock ? "G" : "g"
        case .keyH: return shift || capsLock ? "H" : "h"
        case .keyI: return shift || capsLock ? "I" : "i"
        case .keyJ: return shift || capsLock ? "J" : "j"
        case .keyK: return shift || capsLock ? "K" : "k"
        case .keyL: return shift || capsLock ? "L" : "l"
        case .keyM: return shift || capsLock ? "M" : "m"
        case .keyN: return shift || capsLock ? "N" : "n"
        case .keyO: return shift || capsLock ? "O" : "o"
        case .keyP: return shift || capsLock ? "P" : "p"
        case .keyQ: return shift || capsLock ? "Q" : "q"
        case .keyR: return shift || capsLock ? "R" : "r"
        case .keyS: return shift || capsLock ? "S" : "s"
        case .keyT: return shift || capsLock ? "T" : "t"
        case .keyU: return shift || capsLock ? "U" : "u"
        case .keyV: return shift || capsLock ? "V" : "v"
        case .keyW: return shift || capsLock ? "W" : "w"
        case .keyX: return shift || capsLock ? "X" : "x"
        case .keyY: return shift || capsLock ? "Y" : "y"
        case .keyZ: return shift || capsLock ? "Z" : "z"
        case .key0: return shift ? ")" : "0"
        case .key1: return shift ? "!" : "1"
        case .key2: return shift ? "@" : "2"
        case .key3: return shift ? "#" : "3"
        case .key4: return shift ? "$" : "4"
        case .key5: return shift ? "%" : "5"
        case .key6: return shift ? "^" : "6"
        case .key7: return shift ? "&" : "7"
        case .key8: return shift ? "*" : "8"
        case .key9: return shift ? "(" : "9"
        case .enter: return "\n"
        case .tab: return "\t"
        case .backspace: return "\u{8}"
        default: return nil
        }
    }
    
    /// Get modifier key states
    public static var isShiftDown: Bool {
        return isKeyDown(.shift) || isKeyDown(.leftShift) || isKeyDown(.rightShift)
    }
    
    public static var isControlDown: Bool {
        return isKeyDown(.control) || isKeyDown(.leftControl) || isKeyDown(.rightControl)
    }
    
    public static var isAltDown: Bool {
        return isKeyDown(.alt) || isKeyDown(.leftAlt) || isKeyDown(.rightAlt)
    }
    
    public static var isCapsLockOn: Bool {
        return (GetKeyState(Int32(VirtualKey.capsLock.rawValue)) & 0x01) != 0
    }
}
#endif