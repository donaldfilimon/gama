//  PluginRuntime.swift — GamaPlugin
//  Per-host plugin ownership without globals. The model is GamaCore's
//  SubscriptionContext: a final class owned by one host, confined to
//  that host's executor, releasing everything it owns when it goes away.
//  Two hosts, two runtimes: nothing is shared.

import GamaCore

/// The per-host plugin registry: install, capability mediation, slot
/// rendering, and lifecycle. `@unchecked Sendable` because GamaCore
/// cannot import Synchronization; like ``FrameHost`` itself, a runtime
/// is confined to its owning host's executor and never shared across
/// concurrent hosts. Deinitializing a runtime deactivates every
/// installed plugin, mirroring `SubscriptionContext.deinit`.
public final class PluginRuntime: @unchecked Sendable {
    /// One installed plugin, the context it was issued, and its declared
    /// contributions.
    struct Entry {
        var plugin: any GamaPluginProtocol
        let id: PluginID
        let context: PluginContext
        let scenes: [PluginSceneContribution]
        let declaredCommands: [PluginCommand]
    }

    private let grants: CapabilityGrants
    private let services: HostServices
    private let subscriptions: SubscriptionContext
    private var entries: [Entry] = []

    /// Creates a runtime bound to one host's grant table, services, and
    /// subscription context. `subscriptions` is the owning host's
    /// context (`FrameHost.subscriptions`), so plugin invalidations and
    /// observed signals dirty exactly that host.
    public init(
        grants: CapabilityGrants,
        services: HostServices,
        subscriptions: SubscriptionContext
    ) {
        self.grants = grants
        self.services = services
        self.subscriptions = subscriptions
    }

    deinit {
        deactivateAll()
    }

    /// Identities of every installed plugin, in install order. The order
    /// is deterministic and drives slot child identity.
    public var installed: [PluginID] {
        entries.map(\.id)
    }

    /// Installs one plugin: validates the ABI number, rejects duplicate
    /// identities, checks every required capability against the grant
    /// table and the available services, filters optional capabilities
    /// to the granted service-backed subset, builds the plugin's
    /// ``PluginContext``, and activates it. All-or-nothing: any failure
    /// leaves the runtime unchanged with nothing partially activated.
    public func install(_ plugin: some GamaPluginProtocol) throws(PluginError) {
        let manifest = plugin.manifest
        let id = manifest.id
        guard manifest.abi == PluginManifest.currentABI else {
            throw .abiMismatch(expected: PluginManifest.currentABI, found: manifest.abi)
        }
        guard !entries.contains(where: { $0.id == id }) else {
            throw .duplicate(id)
        }
        for capability in manifest.requires {
            guard grants.permits(id, capability) else {
                throw .missingRequiredCapability(id, capability)
            }
            guard services.supports(capability) else {
                throw .serviceUnavailable(id, capability)
            }
        }
        let granted = manifest.requires
            + manifest.optional.filter { grants.permits(id, $0) && services.supports($0) }
        let context = makeContext(id: id, granted: granted)

        let scenes = plugin.scenes(in: PluginSceneContext(plugin: id))
        for contribution in scenes where contribution.role == .primary {
            throw .primarySceneContribution(id, name: contribution.name)
        }
        let declaredCommands = plugin.commands()

        var activated = plugin
        try activated.activate(in: context)
        entries.append(
            Entry(
                plugin: activated,
                id: id,
                context: context,
                scenes: scenes,
                declaredCommands: declaredCommands
            ))
    }

    /// Uninstalls the plugin with `id`, calling its `deactivate()` and
    /// releasing it. Unknown identities are ignored.
    public func uninstall(_ id: PluginID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.plugin.deactivate()
    }

    /// Renders every installed plugin's contribution for `slot`, each
    /// under `context.child(i)` with `i` the plugin's install index, so
    /// contributed interactive nodes get stable, collision-free node
    /// identities from the existing path derivation. A runtime with no
    /// installed plugins contributes ``RenderNode/empty``.
    public func render(slot: SlotID, in context: BuildContext) -> RenderNode {
        guard !entries.isEmpty else { return .empty }
        return .group(
            children: entries.enumerated().map { index, entry in
                entry.plugin.render(slot: slot, in: context.child(index))
            }
        )
    }

    /// Every contributed command in deterministic order: plugins in
    /// install order, each plugin's commands in declaration order. Each
    /// entry is already bound to its owning plugin's context; the
    /// application or shell chooses the presentation and calls
    /// ``RegisteredPluginCommand/perform()`` on the host's executor.
    public var commands: [RegisteredPluginCommand] {
        entries.flatMap { entry in
            entry.declaredCommands.map { command in
                let context = entry.context
                let action = command.action
                return RegisteredPluginCommand(
                    plugin: entry.id,
                    id: command.id,
                    title: command.title,
                    run: { action(context) }
                )
            }
        }
    }

    /// The namespaced identities of every contributed scene, in install
    /// order, for inspection and window actions.
    public var contributedSceneIDs: [SceneID] {
        sceneEntries.map(\.sceneID)
    }

    /// Contributed scenes with their namespaced identities, consumed by
    /// ``PluginScenes`` when the application's scene graph compiles.
    var sceneEntries: [(sceneID: SceneID, contribution: PluginSceneContribution)] {
        entries.flatMap { entry in
            entry.scenes.map { contribution in
                (sceneID: contribution.sceneID(for: entry.id), contribution: contribution)
            }
        }
    }

    private func makeContext(id: PluginID, granted: [Capability]) -> PluginContext {
        var log: LogAccess?
        var clock: ClockAccess?
        var scopes: [FilesystemScope] = []
        for capability in granted {
            switch capability {
            case .log:
                if let sink = services.log { log = LogAccess(plugin: id, sink: sink) }
            case .clock:
                if let read = services.clock { clock = ClockAccess(read: read) }
            case .filesystem(let scope):
                scopes.append(scope)
            }
        }
        var filesystem: FilesystemAccess?
        if !scopes.isEmpty, let provider = services.filesystem {
            filesystem = FilesystemAccess(scopes: scopes, provider: provider)
        }
        return PluginContext(
            plugin: id,
            log: log,
            clock: clock,
            filesystem: filesystem,
            subscriptions: subscriptions
        )
    }

    private func deactivateAll() {
        while !entries.isEmpty {
            var entry = entries.removeFirst()
            entry.plugin.deactivate()
        }
    }
}
