//  PluginScene.swift — GamaPlugin
//  Scene contributions: additional windows the application agrees to
//  host. Contributed scene identities are namespaced as
//  `plugin/<pluginID>/<name>` so the existing duplicate-identity
//  diagnostics stay collision-free, and a contribution can never claim
//  the primary role: the application's primary scene is not up for
//  grabs. The application opts in by placing ``PluginScenes`` in its
//  `scenes` builder, after which shells treat contributed scenes exactly
//  like `Window` declarations, including `openWindow` and
//  `dismissWindow` context actions.

import GamaCore

/// Context handed to `GamaPluginProtocol.scenes(in:)` when the runtime
/// collects a plugin's scene contributions.
public struct PluginSceneContext: Sendable {
    /// The identity of the plugin being asked for contributions.
    public let plugin: PluginID

    /// Internal on purpose: contexts are issued by ``PluginRuntime``.
    init(plugin: PluginID) {
        self.plugin = plugin
    }
}

/// One window a plugin offers to the application: a plugin-local name,
/// window chrome preferences, and the render-IR payload. The runtime
/// derives the scene identity by namespacing the name under the owning
/// plugin, and rejects any contribution asking for the primary role at
/// install time with a typed error.
public struct PluginSceneContribution {
    /// Plugin-local scene name; the full identity is
    /// `plugin/<pluginID>/<name>`.
    public var name: String
    /// User-visible native-window title.
    public var title: String
    /// The contributed scene's role. `.primary` is never accepted;
    /// install fails with
    /// ``PluginError/primarySceneContribution(_:name:)``.
    public var role: SceneRole
    /// Initial drawable extent in Gama cells.
    public var initialCellSize: Size
    /// Whether the owning shell should permit native resizing.
    public var isResizable: Bool
    /// Builds the contributed window's render IR under the host that
    /// owns the opened window.
    public var content: (BuildContext) -> RenderNode

    /// Creates a scene contribution; the role defaults to auxiliary,
    /// which is the only accepted value in V1.
    public init(
        name: String,
        title: String,
        role: SceneRole = .auxiliary,
        initialCellSize: Size = Size(width: 80, height: 24),
        isResizable: Bool = true,
        content: @escaping (BuildContext) -> RenderNode
    ) {
        self.name = name
        self.title = title
        self.role = role
        self.initialCellSize = initialCellSize
        self.isResizable = isResizable
        self.content = content
    }

    /// The namespaced scene identity this contribution occupies when
    /// installed under `plugin`.
    public func sceneID(for plugin: PluginID) -> SceneID {
        SceneID("plugin/\(plugin.raw)/\(name)")
    }
}

/// Renders a contributed payload as ordinary window content; internal
/// glue between the contribution's IR closure and the scene machinery.
struct ContributedSceneContent: View {
    /// Terminates `body` recursion; this primitive compiles directly.
    typealias Body = Never_
    var body: Never_ { Never_() }
    let content: (BuildContext) -> RenderNode

    func render(in context: BuildContext) -> RenderNode {
        content(context)
    }
}

/// The application's opt-in point for plugin windows. Place it in the
/// `scenes` builder after the runtime's plugins are installed:
///
///     var scenes: some Scene {
///         Window("Main", id: "main", role: .primary) { MainView() }
///         PluginScenes(runtime: plugins)
///     }
///
/// Every contributed scene collects as an on-demand auxiliary window
/// under its namespaced identity, so scene-graph validation, shells, and
/// window actions treat it exactly like an app-declared `Window`.
/// Contributions are read when the scene graph compiles: plugins
/// installed afterwards do not add windows to an already-running shell.
public struct PluginScenes: Scene {
    private let runtime: PluginRuntime

    /// Creates the integration point for one runtime's contributions.
    public init(runtime: PluginRuntime) {
        self.runtime = runtime
    }

    public func _collectScenes(into collector: inout _SceneCollector) throws(
        SceneConfigurationError
    ) {
        for entry in runtime.sceneEntries {
            let contribution = entry.contribution
            let content = contribution.content
            Window(
                contribution.title,
                id: entry.sceneID,
                role: contribution.role,
                launchBehavior: .onDemand,
                initialCellSize: contribution.initialCellSize,
                isResizable: contribution.isResizable
            ) {
                ContributedSceneContent(content: content)
            }._collectScenes(into: &collector)
        }
    }
}
