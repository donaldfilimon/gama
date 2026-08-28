//  PluginRuntime.swift — GamaPlugin
//  Per-host plugin ownership without globals. The model is GamaCore's
//  SubscriptionContext: a final class owned by one host, confined to
//  that host's executor, releasing everything it owns when it goes away.
//  Two hosts, two runtimes: nothing is shared.

import GamaCore

/// The per-host plugin registry: install, capability mediation, slot
/// rendering, and lifecycle. A runtime is confined to its owning host's
/// executor and never shared across concurrent hosts. Deinitializing a
/// runtime deactivates every installed plugin, mirroring
/// `SubscriptionContext.deinit`.
///
/// **Not `Sendable`, and unavailably so.** Installation transfers a plugin's
/// region into the runtime with `sending`; command, scene, and subscription
/// callbacks then remain on the owning host's executor.
public final class PluginRuntime {
    /// Revocation state shared by every command value minted for one
    /// installation. Like the runtime itself, access is host-executor
    /// confined.
    private final class Lease {
        var isActive = true
        func revoke() { isActive = false }
    }

    /// One installed plugin, the context it was issued, and its declared
    /// contributions.
    private struct Entry {
        var plugin: any GamaPluginProtocol
        let id: PluginID
        let slotIdentity: Int
        let context: PluginContext
        let scenes: [PluginSceneContribution]
        let declaredCommands: [PluginCommand]
        let lease: Lease
    }

    private let grants: CapabilityGrants
    private let services: HostServices
    private let subscriptions: SubscriptionContext
    private var entries: [Entry] = []
    private var slotIdentities: [PluginID: Int] = [:]
    private var nextSlotIdentity = 0

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
    /// is deterministic and drives presentation order; slot node identity
    /// is stable per plugin and never renumbered when a peer is removed.
    public var installed: [PluginID] {
        entries.map(\.id)
    }

    /// Installs one plugin: validates the ABI number, rejects duplicate
    /// identities, checks every required capability against the grant
    /// table and the available services, filters optional capabilities
    /// to the granted service-backed subset, builds the plugin's
    /// ``PluginContext``, and activates it. All-or-nothing: any failure
    /// leaves the runtime unchanged with nothing partially activated or
    /// observed. Success invalidates the owning host. The `sending` parameter
    /// transfers ownership of the plugin region into this runtime.
    public func install(_ plugin: sending some GamaPluginProtocol) throws(PluginError) {
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
        do {
            try activated.activate(in: context)
        } catch {
            context.subscriptions.cancelAll()
            throw error
        }
        let slotIdentity = stableSlotIdentity(for: id)
        entries.append(
            Entry(
                plugin: activated,
                id: id,
                slotIdentity: slotIdentity,
                context: context,
                scenes: scenes,
                declaredCommands: declaredCommands,
                lease: Lease()
            ))
        subscriptions.invalidate()
    }

    /// Uninstalls the plugin with `id`, revoking cached commands, cancelling
    /// its observations, calling its `deactivate()`, releasing it, and
    /// invalidating the owning host. Unknown identities are ignored.
    public func uninstall(_ id: PluginID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.lease.revoke()
        entry.context.subscriptions.cancelAll()
        entry.plugin.deactivate()
        subscriptions.invalidate()
    }

    /// Renders every installed plugin's contribution for `slot`, each under
    /// a runtime-assigned child identity retained for that plugin ID. Removing
    /// an earlier peer therefore never renumbers a surviving contribution or
    /// redirects focus/actions to a different plugin. A runtime with no
    /// installed plugins contributes ``RenderNode/empty``.
    public func render(slot: SlotID, in context: BuildContext) -> RenderNode {
        guard !entries.isEmpty else { return .empty }
        return .group(
            children: entries.map { entry in
                entry.plugin.render(slot: slot, in: context.child(entry.slotIdentity))
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
                let lease = entry.lease
                return RegisteredPluginCommand(
                    plugin: entry.id,
                    id: command.id,
                    title: command.title,
                    run: {
                        guard lease.isActive else { return }
                        action(context)
                    }
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
        let hostSubscriptions = subscriptions
        let pluginSubscriptions = SubscriptionContext {
            hostSubscriptions.invalidate()
        }
        return PluginContext(
            plugin: id,
            log: log,
            clock: clock,
            filesystem: filesystem,
            subscriptions: pluginSubscriptions
        )
    }

    private func stableSlotIdentity(for id: PluginID) -> Int {
        if let existing = slotIdentities[id] { return existing }
        let identity = nextSlotIdentity
        nextSlotIdentity += 1
        slotIdentities[id] = identity
        return identity
    }

    private func deactivateAll() {
        while !entries.isEmpty {
            var entry = entries.removeFirst()
            entry.lease.revoke()
            entry.context.subscriptions.cancelAll()
            entry.plugin.deactivate()
        }
    }
}

/// A plugin runtime owns executor-confined lifecycle and callback state; see
/// ``PluginRuntime``. The unavailable conformance makes an accidental
/// `Sendable` use fail with a named compiler diagnostic.
@available(*, unavailable)
extension PluginRuntime: @unchecked Sendable {}
