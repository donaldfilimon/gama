//  GamaView.swift — GamaSwiftUI
//  SwiftUI embedding of one Gama surface. GamaView wraps GamaAppleUI's
//  GamaHostView through NSViewRepresentable (macOS) or UIViewRepresentable
//  (iOS, iPadOS, tvOS, visionOS). The host view owns the frame pump, event
//  routing, and painting; this file only validates the scene graph, creates
//  the host, and tears its session down when SwiftUI removes it.
//
//  The whole file is inert where SwiftUI or a platform view toolkit is
//  unavailable, like GamaAppleShell without AppKit.

#if canImport(SwiftUI) && (canImport(AppKit) || canImport(UIKit))
public import GamaCore
package import GamaAppleUI
public import SwiftUI

/// A SwiftUI view that shows the primary scene of a Gama `App`.
///
/// `GamaView` validates the app's scene graph when it is created, so a
/// misconfigured app (no primary scene, two primaries, a duplicate scene ID)
/// throws a typed `SceneConfigurationError` before SwiftUI ever lays it out.
/// Each time SwiftUI materializes the view it creates one `GamaHostView`,
/// which owns an independent frame host, focus and action state, `@Reactive`
/// state, subscriptions, and draw list; when SwiftUI removes it, that host's
/// subscriptions are cancelled.
///
/// Only the primary scene renders. Auxiliary scenes, window commands, and
/// Gama `LifecycleEvent` delivery belong to `GamaAppleShell`, not to an
/// embedded surface.
///
/// Create a `GamaView` once and hold it; do not build it inside a `body`
/// that SwiftUI re-evaluates. Each initializer call creates or takes the app
/// value and compiles its scene graph, and ``init(_:)`` runs the app's
/// no-argument initializer every time. Once SwiftUI has materialized the
/// view, a replacement `GamaView` value passed by a parent is ignored: the
/// host keeps the surface it installed first.
///
/// A `Signal` stored on the app is shared only between materializations of
/// the same `GamaView` value (one value shown twice, or re-materialized).
/// Two views built by separate ``init(_:)`` calls hold separate app
/// instances and share nothing.
///
/// A file that imports both SwiftUI and GamaCore sees two `App`, `View`,
/// `Scene`, `Text`, and `Window` types, so qualify each use:
///
/// ```swift
/// import GamaCore
/// import GamaSwiftUI
/// import SwiftUI
///
/// @main
/// struct HostApp: SwiftUI.App {
///     // Created once for the process; body re-evaluation reuses it.
///     private let gama = try? GamaView(CounterApp.self)
///
///     var body: some SwiftUI.Scene {
///         SwiftUI.WindowGroup {
///             if let gama {
///                 gama.frame(minWidth: 320, minHeight: 180)
///             } else {
///                 SwiftUI.Text("Invalid Gama app")
///             }
///         }
///     }
/// }
/// ```
@MainActor
public struct GamaView: SwiftUI.View {
    /// The validated primary surface. Every materialized host installs its
    /// own session over it, so reusing the value never shares a frame host.
    private let surface: SceneSurface

    /// Validates `app`'s scene graph and prepares its primary scene for
    /// embedding. Ownership of `app` transfers into the view.
    ///
    /// - Throws: `SceneConfigurationError` when the scene graph is invalid.
    public init<A: GamaCore.App>(app: sending A) throws(SceneConfigurationError) {
        surface = try compileSceneGraph(app).makePrimarySurface()
    }

    /// Creates the app with its no-argument initializer, then validates and
    /// prepares its primary scene exactly as ``init(app:)`` does.
    ///
    /// - Throws: `SceneConfigurationError` when the scene graph is invalid.
    public init<A: GamaCore.App>(_ appType: A.Type) throws(SceneConfigurationError) {
        // Not `self.init(app: A())`: Xcode's Swift 6.4 region analysis treats
        // that fresh value as task-isolated and rejects the `sending` hand-off,
        // while the 6.5-dev snapshot accepts it. Compiling directly needs no
        // transfer at all.
        surface = try compileSceneGraph(A()).makePrimarySurface()
    }

    /// The platform host view, bridged into SwiftUI.
    public var body: some SwiftUI.View {
        GamaHostRepresentable(view: self)
    }

    /// Creates a host view with this view's primary surface installed. The
    /// representable calls this once per materialization; tests call it
    /// directly because a representable context cannot be constructed.
    package func makeHostView() -> GamaHostView {
        let host = GamaHostView(frame: .zero)
        host.install(surface: surface)
        return host
    }

    /// Cancels `host`'s subscriptions and detaches its frame pump, so a
    /// removed view stops rendering and releases its model observers.
    package static func dismantleHostView(_ host: GamaHostView) {
        host.tearDown()
    }
}

#if canImport(AppKit)
    package struct GamaHostRepresentable: NSViewRepresentable {
        package let view: GamaView

        package func makeNSView(context: Context) -> GamaHostView {
            view.makeHostView()
        }

        package func updateNSView(_ nsView: GamaHostView, context: Context) {}

        package static func dismantleNSView(_ nsView: GamaHostView, coordinator: ()) {
            GamaView.dismantleHostView(nsView)
        }
    }
#else
    package struct GamaHostRepresentable: UIViewRepresentable {
        package let view: GamaView

        package func makeUIView(context: Context) -> GamaHostView {
            view.makeHostView()
        }

        package func updateUIView(_ uiView: GamaHostView, context: Context) {}

        package static func dismantleUIView(_ uiView: GamaHostView, coordinator: ()) {
            GamaView.dismantleHostView(uiView)
        }
    }
#endif
#endif
