public enum Action: Equatable, Sendable {
    case tap(NodeID)
    case edit(NodeID, String)
    case toggle(NodeID)
    case select(NodeID, Int)
    case submit(NodeID)
}

public enum Key: Equatable, Sendable {
    case character(Character)
    case enter
    case tab
    case backTab
    case escape
    case backspace
    case up
    case down
    case left
    case right
    case ctrlC
}

public struct Mouse: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case press
        case release
        case drag
    }
    public var kind: Kind
    public var button: Int
    public var x: Int
    public var y: Int
    public init(kind: Kind, button: Int, x: Int, y: Int) {
        self.kind = kind
        self.button = button
        self.x = x
        self.y = y
    }
}

public enum Event: Equatable, Sendable {
    case key(Key)
    case mouse(Mouse)
    case resize(Size)
}
