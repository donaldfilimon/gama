import GamaCore

/// A small but real retained tree for lifecycle leak coverage. This target is
/// an executable, not a test target: its process never loads Swift Testing or
/// XCTest, so LeakSanitizer reports only the runtime and Gama path below.
private struct LeakCheckApp: App {
    var scenes: some Scene {
        Window("Leak check", id: "main", role: .primary) {
            VStack {
                Text("Gama lifecycle probe")
                Button("Focusable action") {}
            }
        }
    }
}

/// Keep the complete host lifetime inside one non-inlined frame. Returning
/// from this function releases the host, its actions, subscriptions, scene
/// closures, and rendered tree before LeakSanitizer performs its exit scan.
@inline(never)
private func exerciseGamaLifetime() throws {
    var host = try FrameHost(app: LeakCheckApp())
    host.handle(.lifecycle(.didLaunch))
    _ = host.pump(size: Size(width: 80, height: 24))

    host.handle(.key(.tab))
    _ = host.pump(size: Size(width: 96, height: 30))

    host.cancelSubscriptions()
    host.handle(.lifecycle(.willTerminate))
}

/// Deliberately leak one real GamaCore allocation. `passRetained` adds an
/// ownership count which is intentionally never balanced; the local strong
/// reference is released on return, leaving LeakSanitizer as the only judge.
/// This exists solely as the CI negative control and is never called by the
/// clean path.
@inline(never)
private func deliberatelyLeakGamaSignal() {
    let signal = Signal(0)
    signal.set(1)
    _ = Unmanaged.passRetained(signal)
}

let arguments = CommandLine.arguments.dropFirst()
let runsNegativeControl = arguments.elementsEqual(["--deliberate-leak"])

guard arguments.isEmpty || runsNegativeControl else {
    fatalError("usage: gama-leak-check [--deliberate-leak]")
}

try exerciseGamaLifetime()

if runsNegativeControl {
    // The script requires both this marker and LeakSanitizer's diagnostic,
    // which distinguishes the intended control from an unrelated crash.
    print("GAMA_LEAK_NEGATIVE_CONTROL_ARMED")
    deliberatelyLeakGamaSignal()
} else {
    print("GAMA_LEAK_CHECK_CLEAN_PATH_COMPLETE")
}
