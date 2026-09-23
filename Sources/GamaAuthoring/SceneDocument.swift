/// One authored entity: an identity, a name, its place in the hierarchy, and
/// at most one component per ``ComponentKind``.
public struct EntityRecord: Hashable, Codable, Sendable {
    public let id: EntityID
    public internal(set) var name: String
    public internal(set) var parent: EntityID?
    /// Ordered children; order is authored state.
    public internal(set) var children: [EntityID]
    public internal(set) var components: [ComponentKind: Component]

    init(
        id: EntityID,
        name: String,
        parent: EntityID? = nil,
        children: [EntityID] = [],
        components: [ComponentKind: Component] = [:]
    ) {
        self.id = id
        self.name = name
        self.parent = parent
        self.children = children
        self.components = components
    }
}

/// The canonical authoring model: a forest of entities with components.
///
/// A value type on purpose (ADR 0001): ``EditorSession`` applies a command or a
/// whole transaction to a copy and commits only on success, so a refused edit
/// never leaves a partial change behind. Mutation happens only through
/// ``DocumentCommand``s; the public surface here is read-only.
public struct SceneDocument: Hashable, Codable, Sendable {
    public private(set) var entities: [EntityID: EntityRecord] = [:]
    /// Ordered top-level entities.
    public private(set) var roots: [EntityID] = []
    private var nextRawID: UInt64 = 1

    public init() {}

    /// The identifier the next created entity will receive. Identifiers are
    /// handed out sequentially, so within one transaction the n-th creation
    /// receives `nextEntityID.rawValue + n`.
    public var nextEntityID: EntityID { EntityID(rawValue: nextRawID) }

    public var count: Int { entities.count }

    public func contains(_ id: EntityID) -> Bool { entities[id] != nil }

    public func entity(_ id: EntityID) -> EntityRecord? { entities[id] }

    public func component(_ kind: ComponentKind, of id: EntityID) -> Component? {
        entities[id]?.components[kind]
    }

    /// The ordered children of `parent`, or the roots when `parent` is `nil`.
    public func children(of parent: EntityID?) -> [EntityID] {
        guard let parent else { return roots }
        return entities[parent]?.children ?? []
    }

    /// `id` and every descendant, parent before child, in authored order.
    public func subtree(_ id: EntityID) -> [EntityID] {
        guard let record = entities[id] else { return [] }
        var result = [id]
        for child in record.children {
            result += subtree(child)
        }
        return result
    }

    /// Whether `ancestor` is `id` itself or lies on its parent chain.
    public func isSelfOrAncestor(_ ancestor: EntityID, of id: EntityID) -> Bool {
        var cursor: EntityID? = id
        while let current = cursor {
            if current == ancestor { return true }
            cursor = entities[current]?.parent
        }
        return false
    }

    /// Compares authored content: entities, hierarchy, and components. The
    /// identifier allocator is excluded, because it deliberately keeps
    /// advancing across undo so identifiers are never reused.
    public func hasSameContent(as other: SceneDocument) -> Bool {
        entities == other.entities && roots == other.roots
    }

    /// Checks every structural invariant. ``EditorSession`` runs this after each
    /// command and transaction and discards a result that fails it.
    public func validate() throws(AuthoringError) {
        var seen: Set<EntityID> = []
        var stack: [(id: EntityID, parent: EntityID?)] = roots.reversed().map { ($0, nil) }
        while let (id, expectedParent) = stack.popLast() {
            guard let record = entities[id] else {
                throw .invariantViolated("\(id) is linked but not stored")
            }
            guard seen.insert(id).inserted else {
                throw .invariantViolated("\(id) is reachable more than once")
            }
            guard record.parent == expectedParent else {
                throw .invariantViolated("\(id) has an asymmetric parent link")
            }
            guard id.rawValue > 0, id.rawValue < nextRawID else {
                throw .invariantViolated("\(id) was not allocated by this document")
            }
            for (kind, component) in record.components {
                guard component.kind == kind else {
                    throw .invariantViolated("\(id) stores a \(component.kind) under \(kind)")
                }
                do {
                    try component.validate()
                } catch {
                    throw .invariantViolated("\(id) holds an invalid \(kind): \(error)")
                }
            }
            stack += record.children.reversed().map { ($0, id) }
        }
        guard seen.count == entities.count else {
            throw .invariantViolated("\(entities.count - seen.count) stored entities are unreachable")
        }
    }

    // MARK: Mutation primitives (commands only)

    mutating func allocateID() -> EntityID {
        defer { nextRawID += 1 }
        return EntityID(rawValue: nextRawID)
    }

    func record(_ id: EntityID) throws(AuthoringError) -> EntityRecord {
        guard let record = entities[id] else { throw .missingEntity(id) }
        return record
    }

    mutating func update(_ id: EntityID, _ body: (inout EntityRecord) -> Void) throws(AuthoringError) {
        guard var record = entities[id] else { throw .missingEntity(id) }
        body(&record)
        entities[id] = record
    }

    /// Inserts an already-detached entity into `parent`'s children (or the
    /// roots) at `index`, appending when `index` is `nil`.
    mutating func attach(_ id: EntityID, to parent: EntityID?, at index: Int?) throws(AuthoringError) {
        guard contains(id) else { throw .missingEntity(id) }
        var siblings: [EntityID]
        if let parent {
            siblings = try record(parent).children
        } else {
            siblings = roots
        }
        let position = index ?? siblings.count
        guard (0...siblings.count).contains(position) else {
            throw .invalidIndex(position, count: siblings.count)
        }
        siblings.insert(id, at: position)
        if let parent {
            try update(parent) { $0.children = siblings }
        } else {
            roots = siblings
        }
        try update(id) { $0.parent = parent }
    }

    /// Removes `id` from its parent's children (or the roots) and returns where
    /// it was, so the caller can put it back.
    mutating func detach(_ id: EntityID) throws(AuthoringError) -> (parent: EntityID?, index: Int) {
        let parent = try record(id).parent
        if let parent {
            var siblings = try record(parent).children
            guard let index = siblings.firstIndex(of: id) else {
                throw .invariantViolated("\(id) missing from its parent's children")
            }
            siblings.remove(at: index)
            try update(parent) { $0.children = siblings }
            return (parent, index)
        }
        guard let index = roots.firstIndex(of: id) else {
            throw .invariantViolated("\(id) missing from the roots")
        }
        roots.remove(at: index)
        return (nil, index)
    }

    mutating func store(_ record: EntityRecord) throws(AuthoringError) {
        guard !contains(record.id) else { throw .duplicateEntity(record.id) }
        entities[record.id] = record
    }

    mutating func discard(_ id: EntityID) {
        entities[id] = nil
    }
}
