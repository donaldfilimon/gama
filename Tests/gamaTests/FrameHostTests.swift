//  FrameHostTests.swift — FrameHost lifecycle and isolation.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

private struct HostProbeApp: App {
    var scenes: some Scene {
        Window("Probe", id: "main", role: .primary) {
            VStack(spacing: 1) {
                Button("One", action: {})
                Button("Two", action: {})
            }
        }
    }
}

private struct HostIsolationApp: App {
    let value: Signal<Int>
    init() { value = Signal(0) }
    init(value: Signal<Int>) { self.value = value }

    var scenes: some Scene {
        Window("Isolation", id: "main", role: .primary) {
            Button("Increment") { value.update { $0 += 1 } }
        }
    }
}

@Suite("FrameHost")
struct FrameHostTests {
    @Test("focus cycles with tab")
    func focusCyclesWithTab() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.tab))
        // Bound before #expect throughout this suite: the macro's
        // property-access form needs a Copyable base, and FrameHost is
        // deliberately noncopyable.
        let dirtyAfterTab = host.needsFrame
        #expect(dirtyAfterTab)
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 20, height: 6))
        let quitRequested = host.wantsQuit
        #expect(!quitRequested)
    }

    @Test("ctrl-C requests quit")
    func ctrlCRequestsQuit() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.ctrl("c")))
        let quitRequested = host.wantsQuit
        #expect(quitRequested)
    }

    @Test("resize marks dirty")
    func resizeMarksDirty() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        let cleanAfterPump = host.needsFrame
        #expect(!cleanAfterPump)
        host.handle(.resize(Size(width: 30, height: 8)))
        let dirtyAfterResize = host.needsFrame
        #expect(dirtyAfterResize)
    }

    @Test("resize event records lastSize and dirties")
    func resizeEventRecordsLastSizeAndDirties() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        let sizeAfterPump = host.lastSize
        let cleanAfterPump = host.needsFrame
        #expect(sizeAfterPump == Size(width: 20, height: 6))
        #expect(!cleanAfterPump)
        host.handle(.resize(Size(width: 30, height: 8)))
        let sizeAfterResize = host.lastSize
        let dirtyAfterResize = host.needsFrame
        #expect(sizeAfterResize == Size(width: 30, height: 8))
        #expect(dirtyAfterResize)
    }

    @Test("hosts keep actions and dirty state isolated")
    func hostsKeepActionsAndDirtyStateIsolated() throws {
        let leftValue = Signal(0)
        let rightValue = Signal(0)
        var left = try FrameHost(app: HostIsolationApp(value: leftValue))
        var right = try FrameHost(app: HostIsolationApp(value: rightValue))
        _ = left.pump(size: Size(width: 20, height: 3))
        _ = right.pump(size: Size(width: 20, height: 3))

        left.handle(.key(.enter))

        #expect(leftValue.get() == 1)
        #expect(rightValue.get() == 0)
        let dirtyStates = (left.needsFrame, right.needsFrame)
        #expect(dirtyStates.0)
        #expect(!dirtyStates.1)
    }
}
