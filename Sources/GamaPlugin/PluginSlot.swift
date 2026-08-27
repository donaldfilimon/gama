//  PluginSlot.swift — GamaPlugin
//  The application's opt-in point for plugin UI. A slot is an ordinary
//  primitive view: its render pass asks the runtime for every installed
//  plugin's contribution, and interactions inside plugin IR register
//  through the slot's BuildContext into the owning host's action store,
//  with zero new identity or event machinery.

import GamaCore

/// A named region of the application's view tree that installed plugins
/// may render into. Place one in ordinary view content:
///
///     VStack {
///         Header()
///         PluginSlot("sidebar", runtime: plugins)
///         Footer()
///     }
///
/// Each plugin's contribution renders under a runtime-assigned child identity
/// retained for its plugin ID, so node identities stay stable across rebuilds,
/// peer removal, and reinstall in the same runtime.
public struct PluginSlot: View {
    /// Terminates `body` recursion; this primitive compiles in
    /// `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    private let slot: SlotID
    private let runtime: PluginRuntime

    /// Creates a slot that renders `runtime`'s contributions for `slot`.
    public init(_ slot: SlotID, runtime: PluginRuntime) {
        self.slot = slot
        self.runtime = runtime
    }

    /// Compiles to the grouped contributions of every installed plugin.
    public func render(in context: BuildContext) -> RenderNode {
        runtime.render(slot: slot, in: context)
    }
}
