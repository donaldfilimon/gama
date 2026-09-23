#if canImport(RealityKit)
public import GamaAuthoring
public import RealityKit

/// Projects a ``SceneDocument`` into a RealityKit entity tree and keeps it
/// current from the ``SceneChange`` feed.
///
/// The bridge is a read-only projection (ADR 0002): it never mutates the
/// document, and nothing reads authored state back out of RealityKit. A
/// viewport adds ``root`` to its scene and forwards picks through
/// ``id(for:)``, so a selection always resolves to an ``EntityID`` and then to
/// the document (spec §7).
@MainActor
public final class RealityBridge {
    /// The container for every projected entity. The bridge owns no view.
    public let root = Entity()

    private var entities: [EntityID: Entity] = [:]
    private var identities: [ObjectIdentifier: EntityID] = [:]
    private var meshes = PrimitiveMeshes()
    /// Containers whose children changed during the current pass.
    private var touched: Set<ObjectIdentifier> = []

    public init() {
        root.name = "GamaReality.root"
    }

    /// The number of projected entities, excluding ``root``.
    public var count: Int { entities.count }

    /// The RealityKit entity projecting `id`, if it exists.
    public func entity(for id: EntityID) -> Entity? { entities[id] }

    /// The authored identity behind a RealityKit entity, for viewport picking.
    /// `nil` for ``root`` and for entities the bridge did not create.
    public func id(for entity: Entity) -> EntityID? { identities[ObjectIdentifier(entity)] }

    /// Discards the current projection and projects the whole document. Use it
    /// once when a document is opened; use ``apply(_:from:)`` for edits.
    public func rebuild(from document: SceneDocument) {
        for child in Array(root.children) {
            child.removeFromParent()
        }
        entities = [:]
        identities = [:]
        touched = []
        for rootID in document.roots {
            for id in document.subtree(rootID) {
                create(id, in: document)
            }
        }
        resequenceTouchedContainers(in: document)
    }

    /// Applies committed changes incrementally, touching only the entities they
    /// name. Values are read from `document`, which must be the session's
    /// document *after* the changes were committed (the feed names what
    /// changed, not the new value). A change naming an entity the document no
    /// longer holds is skipped: a later change in the same batch removed it.
    public func apply(_ changes: [SceneChange], from document: SceneDocument) {
        for change in changes {
            switch change {
            case .entityCreated(let id):
                if entities[id] == nil {
                    create(id, in: document)
                }
            case .entityDeleted(let id):
                remove(id)
            case .renamed(let id):
                if let record = document.entity(id), let entity = entities[id] {
                    entity.name = record.name
                }
            case .reparented(let id):
                if let record = document.entity(id), let entity = entities[id] {
                    place(entity, for: record, in: document)
                }
            case .componentSet(let id, _), .componentRemoved(let id, _):
                if let record = document.entity(id), let entity = entities[id] {
                    project(record, onto: entity)
                }
            }
        }
        resequenceTouchedContainers(in: document)
    }

    // MARK: Projection

    private func create(_ id: EntityID, in document: SceneDocument) {
        // Created then deleted within one batch: nothing to project.
        guard let record = document.entity(id) else { return }
        let entity = Entity()
        entities[id] = entity
        identities[ObjectIdentifier(entity)] = id
        entity.name = record.name
        project(record, onto: entity)
        place(entity, for: record, in: document)
    }

    private func remove(_ id: EntityID) {
        guard let entity = entities.removeValue(forKey: id) else { return }
        identities[ObjectIdentifier(entity)] = nil
        if let parent = entity.parent {
            touched.insert(ObjectIdentifier(parent))
        }
        entity.removeFromParent()
    }

    /// Puts `entity` under its authored parent. Sibling order is settled
    /// afterwards by ``resequenceTouchedContainers(in:)``.
    private func place(_ entity: Entity, for record: EntityRecord, in document: SceneDocument) {
        // The feed reports parents first, so the parent normally exists. If a
        // batch ever arrives out of order, project the parent now rather than
        // silently parking the child under the root.
        if let parent = record.parent, entities[parent] == nil {
            create(parent, in: document)
        }
        let container = record.parent.flatMap { entities[$0] } ?? root
        guard entity.parent !== container else {
            touched.insert(ObjectIdentifier(container))
            return
        }
        if let previous = entity.parent {
            touched.insert(ObjectIdentifier(previous))
        }
        // The authored transform is parent-relative, so the local transform is
        // kept and the world transform follows the new parent.
        entity.setParent(container, preservingWorldTransform: false)
        touched.insert(ObjectIdentifier(container))
    }

    /// Restores authored sibling order in every container this pass touched.
    ///
    /// RealityKit's `ChildCollection` does not keep sibling order when a child
    /// is removed (the last child can move into the vacated slot), so order is
    /// not maintained per operation. Instead, each touched container is
    /// compared with the document once per pass and re-sequenced only if it
    /// differs. Untouched containers are never visited.
    private func resequenceTouchedContainers(in document: SceneDocument) {
        defer { touched = [] }
        for key in touched {
            let container: Entity
            let authored: [EntityID]
            if key == ObjectIdentifier(root) {
                container = root
                authored = document.roots
            } else if let id = identities[key], let entity = entities[id] {
                container = entity
                authored = document.children(of: id)
            } else {
                continue  // removed later in the same pass
            }
            let desired = authored.compactMap { entities[$0] }.filter { $0.parent === container }
            let current = Array(container.children)
            guard !current.elementsEqual(desired, by: ===) else { continue }
            let foreign = current.filter { child in !desired.contains { $0 === child } }
            for child in current {
                child.removeFromParent(preservingWorldTransform: false)
            }
            container.children.append(contentsOf: desired + foreign)
        }
    }

    private func project(_ record: EntityRecord, onto entity: Entity) {
        if case .transform(let transform)? = record.components[.transform] {
            entity.transform = RealityKit.Transform(
                scale: transform.scale,
                rotation: simd_quatf(
                    ix: transform.rotation.x,
                    iy: transform.rotation.y,
                    iz: transform.rotation.z,
                    r: transform.rotation.w
                ),
                translation: transform.position
            )
        } else {
            entity.transform = RealityKit.Transform.identity
        }

        if case .mesh(let primitive)? = record.components[.mesh] {
            let material: GamaAuthoring.Material
            if case .material(let authored)? = record.components[.material] {
                material = authored
            } else {
                material = GamaAuthoring.Material()
            }
            entity.components.set(ModelComponent(
                mesh: meshes.mesh(for: primitive),
                materials: [material.physicallyBased]
            ))
        } else {
            entity.components.remove(ModelComponent.self)
        }

        if case .visibility(let visibility)? = record.components[.visibility] {
            entity.isEnabled = visibility.visible
        } else {
            entity.isEnabled = true
        }
    }
}
#endif
