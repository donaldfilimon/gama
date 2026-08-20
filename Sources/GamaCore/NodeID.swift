public struct NodeID: Hashable, Sendable, ExpressibleByStringLiteral {
    public var raw: String
    public init(_ raw: String) {
        self.raw = raw
    }
    public init(stringLiteral value: String) {
        self.raw = value
    }
}
