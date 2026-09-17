#if arch(wasm32)
import GamaCore
import GamaWASM

// The first and only install must fail after WASI startup, leaving no host.
// No reset hook or successful install may manufacture this lifecycle state.
struct MissingPrimaryApp: App {
    var scenes: some Scene {
        Window("Auxiliary", id: "auxiliary") { Text("must never render") }
    }
}

do {
    try GamaWeb.install(app: MissingPrimaryApp())
    fatalError("first install unexpectedly succeeded")
} catch {
    guard error == .noPrimaryScene else {
        fatalError("first install threw an unexpected SceneConfigurationError")
    }
    print("WASM fixture: SceneConfigurationError.noPrimaryScene")
}
#else
print("GamaWASMFailedInstall must be built for wasm32")
#endif
