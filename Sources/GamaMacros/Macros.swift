//  Macros.swift — GamaMacros
//  Public macro surface. Implementations live in GamaMacrosImpl and run
//  host-side at compile time — nothing here costs anything at runtime,
//  which is exactly what Embedded targets want.

@_exported import GamaCore

/// Marks a struct as a Gama component:
///  • adds `GamaCore.View` conformance via extension
///  • synthesizes a public memberwise initializer for stored properties
///  • when the struct has `@Reactive` properties, synthesizes the
///    `render(in:)` that binds each slot to the owning host before
///    rendering `body`; a hand-written `render(in:)` beside `@Reactive`
///    properties is an error (`component.render-collision`)
///
///     @Component
///     struct Badge {
///         var label: String
///         var body: some View { Text(label).bold() }
///     }
@attached(member, names: named(init), named(render))
@attached(extension, conformances: View)
public macro Component() =
    #externalMacro(module: "GamaMacrosImpl", type: "ComponentMacro")

/// Reactive stored property whose state is owned by the host that renders
/// it, keyed by the component's identity in the tree — **per surface**, not
/// per instance. Requires a struct marked `@Component`; the `render(in:)`
/// that `@Component` synthesizes binds each slot to the host.
///
///     @Component
///     struct Counter {
///         @Reactive var count: Int = 0
///         var body: some View {
///             Button("count: \(count)") { count += 1 }
///         }
///     }
///
///     struct CounterApp: App {
///         var scenes: some Scene {
///             Window("Counter", id: "main", role: .primary) { Counter() }
///         }
///     }
///
/// Scene content is rebuilt on every frame, and that inline construction is
/// the primary shape: each frame's fresh `Counter` binds to the same
/// host-owned signal, so the mutation is painted on the next frame. Two
/// windows of one ``GamaCore/WindowGroup`` get independent state for the
/// same declaration. A hoisted instance stored on the app remains valid and
/// also writes per surface; its value before the first render seeds each
/// surface's initial state.
///
/// Sharing has an explicit spelling: store a ``GamaCore/Signal`` on the app
/// and observe it from each host. `@Reactive` is per-surface; a `Signal` on
/// the `App` is shared. Raw `Signal` stored properties inside a component
/// are unsupported — for `TextField` and `Toggle`, pass the slot's binding:
///
///     @Reactive var name: String = ""
///     var body: some View { TextField("name", text: _name.binding()) }
///
/// Identity is structural: a branch flip or a positional `ForEach` reorder
/// reconstructs state and is reported through `FrameHost.transientStateIDs`.
/// Use `IdentifiedForEach` or `.stateScope(_:)` to pin a subtree to an
/// explicit identity. Rendering without a host (a bare `BuildContext()`)
/// keeps the slot on instance-local storage.
///
/// Compile errors: `reactive.requires-component` when the property sits
/// outside a struct marked `@Component` (including in a class), and
/// `component.render-collision` when the component hand-writes `render(in:)`.
/// Expands to a `private let _name: ReactiveSlot<T>` peer plus accessors.
@attached(peer, names: prefixed(`_`))
@attached(accessor, names: named(init), named(get), named(set))
public macro Reactive() =
    #externalMacro(module: "GamaMacrosImpl", type: "ReactiveMacro")

/// Compile-time hex color literal. Malformed hex is a *build error*, not
/// a runtime surprise:
///
///     let accent = #rgb("FF8800")   // → Color(r: 255, g: 136, b: 0)
@freestanding(expression)
public macro rgb(_ hex: String) -> Color =
    #externalMacro(module: "GamaMacrosImpl", type: "RGBMacro")
