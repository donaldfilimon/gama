import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Mouse button types
#if canImport(WinSDK)
public enum MouseButton {
    case left
    case right
    case middle
    case x1
    case x2
}

/// Keyboard key information
public struct KeyInfo {
    public let virtualKey: UInt16
    public let scanCode: UInt8
    public let flags: UInt32
    
    public var isExtended: Bool {
        return (flags & 0x01) != 0
    }
    
    public var wasDown: Bool {
        return (flags & 0x80) != 0
    }
    
    public var isAltDown: Bool {
        return (flags & 0x20) != 0
    }
    
    public var isRepeat: Bool {
        return (flags & 0x4000) != 0
    }
}

/// Mouse event information
public struct MouseEvent {
    public let position: Point
    public let button: MouseButton?
    public let wheelDelta: Int16
    public let keys: KeyState
    
    public struct KeyState: OptionSet {
        public let rawValue: UInt16
        
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        
        public static let leftButton = KeyState(rawValue: 0x0001)
        public static let rightButton = KeyState(rawValue: 0x0002)
        public static let shift = KeyState(rawValue: 0x0004)
        public static let control = KeyState(rawValue: 0x0008)
        public static let middleButton = KeyState(rawValue: 0x0010)
        public static let xButton1 = KeyState(rawValue: 0x0020)
        public static let xButton2 = KeyState(rawValue: 0x0040)
    }
}

/// Keyboard event information
public struct KeyboardEvent {
    public let keyInfo: KeyInfo
    public let character: Character?
    
    public var virtualKey: VirtualKey {
        return VirtualKey(rawValue: keyInfo.virtualKey) ?? .unknown
    }
}

/// Virtual key codes
public enum VirtualKey: UInt16 {
    case unknown = 0
    case leftButton = 0x01
    case rightButton = 0x02
    case cancel = 0x03
    case middleButton = 0x04
    case xButton1 = 0x05
    case xButton2 = 0x06
    case backspace = 0x08
    case tab = 0x09
    case clear = 0x0C
    case enter = 0x0D
    case shift = 0x10
    case control = 0x11
    case alt = 0x12
    case pause = 0x13
    case capsLock = 0x14
    case escape = 0x1B
    case space = 0x20
    case pageUp = 0x21
    case pageDown = 0x22
    case end = 0x23
    case home = 0x24
    case left = 0x25
    case up = 0x26
    case right = 0x27
    case down = 0x28
    case select = 0x29
    case print = 0x2A
    case execute = 0x2B
    case printScreen = 0x2C
    case insert = 0x2D
    case delete = 0x2E
    case help = 0x2F
    case key0 = 0x30
    case key1 = 0x31
    case key2 = 0x32
    case key3 = 0x33
    case key4 = 0x34
    case key5 = 0x35
    case key6 = 0x36
    case key7 = 0x37
    case key8 = 0x38
    case key9 = 0x39
    case keyA = 0x41
    case keyB = 0x42
    case keyC = 0x43
    case keyD = 0x44
    case keyE = 0x45
    case keyF = 0x46
    case keyG = 0x47
    case keyH = 0x48
    case keyI = 0x49
    case keyJ = 0x4A
    case keyK = 0x4B
    case keyL = 0x4C
    case keyM = 0x4D
    case keyN = 0x4E
    case keyO = 0x4F
    case keyP = 0x50
    case keyQ = 0x51
    case keyR = 0x52
    case keyS = 0x53
    case keyT = 0x54
    case keyU = 0x55
    case keyV = 0x56
    case keyW = 0x57
    case keyX = 0x58
    case keyY = 0x59
    case keyZ = 0x5A
    case leftWindows = 0x5B
    case rightWindows = 0x5C
    case applications = 0x5D
    case sleep = 0x5F
    case numPad0 = 0x60
    case numPad1 = 0x61
    case numPad2 = 0x62
    case numPad3 = 0x63
    case numPad4 = 0x64
    case numPad5 = 0x65
    case numPad6 = 0x66
    case numPad7 = 0x67
    case numPad8 = 0x68
    case numPad9 = 0x69
    case multiply = 0x6A
    case add = 0x6B
    case separator = 0x6C
    case subtract = 0x6D
    case decimal = 0x6E
    case divide = 0x6F
    case f1 = 0x70
    case f2 = 0x71
    case f3 = 0x72
    case f4 = 0x73
    case f5 = 0x74
    case f6 = 0x75
    case f7 = 0x76
    case f8 = 0x77
    case f9 = 0x78
    case f10 = 0x79
    case f11 = 0x7A
    case f12 = 0x7B
    case f13 = 0x7C
    case f14 = 0x7D
    case f15 = 0x7E
    case f16 = 0x7F
    case f17 = 0x80
    case f18 = 0x81
    case f19 = 0x82
    case f20 = 0x83
    case f21 = 0x84
    case f22 = 0x85
    case f23 = 0x86
    case f24 = 0x87
    case numLock = 0x90
    case scrollLock = 0x91
    case leftShift = 0xA0
    case rightShift = 0xA1
    case leftControl = 0xA2
    case rightControl = 0xA3
    case leftAlt = 0xA4
    case rightAlt = 0xA5
    case browserBack = 0xA6
    case browserForward = 0xA7
    case browserRefresh = 0xA8
    case browserStop = 0xA9
    case browserSearch = 0xAA
    case browserFavorites = 0xAB
    case browserHome = 0xAC
    case volumeMute = 0xAD
    case volumeDown = 0xAE
    case volumeUp = 0xAF
    case mediaNextTrack = 0xB0
    case mediaPreviousTrack = 0xB1
    case mediaStop = 0xB2
    case mediaPlayPause = 0xB3
    case launchMail = 0xB4
    case launchMediaSelect = 0xB5
    case launchApp1 = 0xB6
    case launchApp2 = 0xB7
    case oem1 = 0xBA
    case oemPlus = 0xBB
    case oemComma = 0xBC
    case oemMinus = 0xBD
    case oemPeriod = 0xBE
    case oem2 = 0xBF
    case oem3 = 0xC0
    case oem4 = 0xDB
    case oem5 = 0xDC
    case oem6 = 0xDD
    case oem7 = 0xDE
    case oem8 = 0xDF
    case oem102 = 0xE2
    case processKey = 0xE5
    case packet = 0xE7
    case attn = 0xF6
    case crsel = 0xF7
    case exsel = 0xF8
    case eraseEOF = 0xF9
    case play = 0xFA
    case zoom = 0xFB
    case noname = 0xFC
    case pa1 = 0xFD
    case oemClear = 0xFE
}
#endif