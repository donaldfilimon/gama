//  StudioApp.swift — GamaStudioEditor
//
//  Dependency-spike placeholder: the real Studio scene graph will replace
//  this once the RealityKit viewport is wired in. For now it proves the
//  gama App/Window/Text API resolves and compiles when gama is consumed as
//  a dependency under this package's Swift 6.5-dev snapshot.

#if canImport(AppKit)

public import GamaCore

/// The Gama Studio application root. Declares a single primary window that
/// will later host the authoring canvas and RealityKit viewport.
public struct StudioApp: App {
    /// Creates the application; Gama constructs apps with no arguments.
    public init() {}

    /// One primary window, `"Gama Studio"`, showing a placeholder label
    /// until the authoring canvas is wired in.
    public var scenes: some Scene {
        Window("Gama Studio", id: "main", role: .primary) {
            Text("Gama Studio")
        }
    }
}

#endif
