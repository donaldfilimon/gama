/// A semantic, undoable edit to a ``SceneDocument``.
///
/// Every mutation is a command (spec invariant 3). A command applies itself
/// and returns its exact inverse, and ``EditorSession`` records that inverse for
/// undo. Redo applies the inverse of the inverse, never the original again, so
/// a redone creation gets back its original identifier rather than a new one.
///
/// Commands are synchronous (ADR 0001). Work that *produces* commands, such as
/// import, graph evaluation, or AI planning, may be asynchronous; the mutation
/// itself is not.
public protocol DocumentCommand: Sendable {
    /// A short human-readable name, used for undo and redo menu titles.
    var label: String { get }

    /// Applies the edit, appends what changed to `changes`, and returns the
    /// command that reverses it. A throwing command may leave `document` and
    /// `changes` partly modified; the session always applies commands to a copy
    /// and discards it on failure.
    func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand
}

// MARK: - Creation and deletion

/// Creates one entity, appended to `parent` (or the roots) unless `index` is
/// given. Its identifier is ``SceneDocument/nextEntityID`` at the time it runs.
public struct CreateEntity: DocumentCommand {
    public var name: String
    public var parent: EntityID?
    public var index: Int?
    public var components: [Component]

    public init(
        name: String,
        parent: EntityID? = nil,
        index: Int? = nil,
        components: [Component] = [.transform(.identity)]
    ) {
        self.name = name
        self.parent = parent
        self.index = index
        self.components = components
    }

    public var label: String { "Create \(name)" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        var stored: [ComponentKind: Component] = [:]
        for component in components {
            try component.validate()
            stored[component.kind] = component
        }
        if let parent, !document.contains(parent) {
            throw .missingEntity(parent)
        }
        let id = document.allocateID()
        try document.store(EntityRecord(id: id, name: name, components: stored))
        try document.attach(id, to: parent, at: index)
        changes.append(.entityCreated(id))
        return DeleteEntity(id)
    }
}

/// Deletes an entity together with its whole subtree.
public struct DeleteEntity: DocumentCommand {
    public var id: EntityID

    public init(_ id: EntityID) {
        self.id = id
    }

    public var label: String { "Delete" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        let ids = document.subtree(id)
        guard !ids.isEmpty else { throw .missingEntity(id) }
        var records: [EntityRecord] = []
        for member in ids {
            records.append(try document.record(member))
        }
        let (parent, index) = try document.detach(id)
        for member in ids.reversed() {
            document.discard(member)
            changes.append(.entityDeleted(member))
        }
        return RestoreSubtree(records: records, parent: parent, index: index)
    }
}

/// Puts back a subtree exactly as it was captured, with its original
/// identifiers. Only produced as the inverse of a deletion.
struct RestoreSubtree: DocumentCommand {
    /// Parent before child; the first record is the subtree root.
    var records: [EntityRecord]
    var parent: EntityID?
    var index: Int

    var label: String { "Restore" }

    func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        guard let root = records.first else {
            throw .invariantViolated("empty subtree snapshot")
        }
        if let parent, !document.contains(parent) {
            throw .missingEntity(parent)
        }
        for record in records {
            try document.store(record)
            changes.append(.entityCreated(record.id))
        }
        try document.attach(root.id, to: parent, at: index)
        return DeleteEntity(root.id)
    }
}

/// Copies an entity and its subtree with fresh identifiers, placed directly
/// after the original under the same parent. Names are copied unchanged.
public struct DuplicateEntity: DocumentCommand {
    public var id: EntityID

    public init(_ id: EntityID) {
        self.id = id
    }

    public var label: String { "Duplicate" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        let original = document.subtree(id)
        guard !original.isEmpty else { throw .missingEntity(id) }
        var mapping: [EntityID: EntityID] = [:]
        for member in original {
            mapping[member] = document.allocateID()
        }
        let source = try document.record(id)
        for member in original {
            let record = try document.record(member)
            let copy = EntityRecord(
                id: mapping[member]!,
                name: record.name,
                parent: record.parent.flatMap { mapping[$0] },
                children: record.children.map { mapping[$0]! },
                components: record.components
            )
            try document.store(copy)
            changes.append(.entityCreated(copy.id))
        }
        let siblings = document.children(of: source.parent)
        guard let position = siblings.firstIndex(of: id) else {
            throw .invariantViolated("\(id) missing from its siblings")
        }
        let root = mapping[id]!
        try document.attach(root, to: source.parent, at: position + 1)
        return DeleteEntity(root)
    }
}

// MARK: - Properties

/// Renames an entity.
public struct RenameEntity: DocumentCommand {
    public var id: EntityID
    public var name: String

    public init(_ id: EntityID, to name: String) {
        self.id = id
        self.name = name
    }

    public var label: String { "Rename" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        let old = try document.record(id).name
        try document.update(id) { $0.name = name }
        changes.append(.renamed(id))
        return RenameEntity(id, to: old)
    }
}

/// Adds or replaces the component of `component.kind` on an entity. This is
/// the spec's `SetTransformCommand` when the component is a transform.
public struct SetComponent: DocumentCommand {
    public var id: EntityID
    public var component: Component

    public init(_ id: EntityID, _ component: Component) {
        self.id = id
        self.component = component
    }

    public var label: String { "Set \(component.kind.displayName)" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        try component.validate()
        let old = try document.record(id).components[component.kind]
        try document.update(id) { $0.components[component.kind] = component }
        changes.append(.componentSet(id, component.kind))
        if let old {
            return SetComponent(id, old)
        }
        return RemoveComponent(id, component.kind)
    }
}

/// Removes the component of `kind` from an entity.
public struct RemoveComponent: DocumentCommand {
    public var id: EntityID
    public var kind: ComponentKind

    public init(_ id: EntityID, _ kind: ComponentKind) {
        self.id = id
        self.kind = kind
    }

    public var label: String { "Remove \(kind.displayName)" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        guard let old = try document.record(id).components[kind] else {
            throw .componentAbsent(id, kind)
        }
        try document.update(id) { $0.components[kind] = nil }
        changes.append(.componentRemoved(id, kind))
        return SetComponent(id, old)
    }
}

// MARK: - Hierarchy

/// Moves an entity under `parent` (or to the roots when `nil`) at `index` in
/// the destination's children, appending when `index` is `nil`. The index is
/// interpreted after the entity has been removed from its current place.
public struct ReparentEntity: DocumentCommand {
    public var id: EntityID
    public var parent: EntityID?
    public var index: Int?

    public init(_ id: EntityID, to parent: EntityID?, at index: Int? = nil) {
        self.id = id
        self.parent = parent
        self.index = index
    }

    public var label: String { "Reparent" }

    public func apply(
        to document: inout SceneDocument,
        changes: inout [SceneChange]
    ) throws(AuthoringError) -> any DocumentCommand {
        guard document.contains(id) else { throw .missingEntity(id) }
        if let parent {
            guard document.contains(parent) else { throw .missingEntity(parent) }
            guard !document.isSelfOrAncestor(id, of: parent) else {
                throw .wouldCreateCycle(entity: id, parent: parent)
            }
        }
        let origin = try document.detach(id)
        try document.attach(id, to: parent, at: index)
        changes.append(.reparented(id))
        return ReparentEntity(id, to: origin.parent, at: origin.index)
    }
}
