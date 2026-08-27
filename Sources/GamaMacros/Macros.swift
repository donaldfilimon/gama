//  Macros.swift — GamaMacros
//  Public macro surface. Implementations live in GamaMacrosImpl and run
//  host-side at compile time — nothing here costs anything at runtime,
//  which is exactly what Embedded targets want.

@_exported import GamaCore

/// Marks a struct as a Gama component:
///  • adds `GamaCore.View` conformance via extension
///  • synthesizes a public memberwise initializer for stored properties
///
///     @Component
///     struct Badge {
///         var label: String
///         var body: some View { Text(label).bold() }
///     }
@attached(member, names: named(init))
@attached(extension, conformances: View)
public macro Component() =
    #externalMacro(module: "GamaMacrosImpl", type: "ComponentMacro")

/// Reactive stored property backed by a `Signal`, wired into the runtime
/// invalidator. Compile-time expansion of the @State pattern — usable in
/// classes and structs alike, no property-wrapper overhead.
///
///     @Component
///     struct Counter {
///         @Reactive var count: Int = 0
///         var body: some View {
///             Button("count: \(count)") { count += 1 }
///         }
///     }
///
/// The state lives in the component *instance*, which must outlive the
/// frame. Scene content is rebuilt on every frame, so a component
/// constructed inside a `Window` or `WindowGroup` closure is replaced —
/// state included — before the next frame paints, and every mutation is
/// silently discarded. Store the instance where it survives instead:
///
///     struct CounterApp: App {
///         private let counter = Counter()   // not `{ Counter() }` below
///         var scenes: some Scene {
///             Window("Counter", id: "main", role: .primary) { counter }
///         }
///     }
///
/// App-level ``GamaCore/Signal`` values captured by the closure have the
/// same lifetime and work equally well.
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
