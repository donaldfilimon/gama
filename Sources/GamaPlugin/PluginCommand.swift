//  PluginCommand.swift — GamaPlugin
//  Named, host-dispatched actions. Plugins declare plain command data;
//  the runtime binds each command to its owning plugin's context, and
//  the application chooses the presentation (menu, palette, key
//  binding). Dispatch runs on the host's executor like every other
//  action.

/// Names one plugin-contributed command.
public struct CommandID: Hashable, Sendable, ExpressibleByStringLiteral {
    /// The plugin-local command name.
    public var raw: String

    /// Creates a command identity from its raw string.
    public init(_ raw: String) { self.raw = raw }
    /// Creates a command identity from a string literal.
    public init(stringLiteral value: String) { self.raw = value }
}

/// One command a plugin contributes: an identity, a human-readable
/// title, and the action the host runs with the owning plugin's
/// ``PluginContext`` when the command is dispatched.
public struct PluginCommand {
    /// Plugin-local command identity.
    public var id: CommandID
    /// Human-readable title for menus and palettes.
    public var title: String
    /// Runs on dispatch, receiving the owning plugin's context.
    public var action: (PluginContext) -> Void

    /// Creates a command contribution.
    public init(
        id: CommandID,
        title: String,
        action: @escaping (PluginContext) -> Void
    ) {
        self.id = id
        self.title = title
        self.action = action
    }
}

/// A command as surfaced by ``PluginRuntime/commands``: the contribution
/// plus its owning plugin, already bound to that plugin's context so a
/// presentation surface only calls ``perform()``. A value cached by a menu
/// or palette becomes inert when its plugin is uninstalled or its runtime is
/// destroyed.
public struct RegisteredPluginCommand {
    /// The plugin that contributed this command.
    public let plugin: PluginID
    /// The contribution's plugin-local identity.
    public let id: CommandID
    /// Human-readable title for menus and palettes.
    public let title: String
    private let run: () -> Void

    /// Internal on purpose: registered commands are minted by
    /// ``PluginRuntime`` with the owning plugin's context bound in.
    init(plugin: PluginID, id: CommandID, title: String, run: @escaping () -> Void) {
        self.plugin = plugin
        self.id = id
        self.title = title
        self.run = run
    }

    /// Dispatches the command with the owning plugin's context, on the
    /// caller's (the host's) executor. Does nothing after revocation.
    public func perform() {
        run()
    }
}
