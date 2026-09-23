//  NativeRegionTests.swift — native regions (ADR 0016): build, host table, fallback parity.

import GamaCore
import GamaDraw
import GamaMLIR
import Testing

private let viewport = NativeRegionID("viewport")

/// Records registrations; a class so the escaping hook can append.
private final class RegionLog { var entries: [(NodeID, NativeRegionID)] = [] }

@Suite("Native region build")
struct NativeRegionBuildTests {
    @Test("host-less render is the interactive node around a flexible fallback")
    func hostlessRender() {
        let region = NativeRegion(viewport) { Text("3D") }
        let expected = RenderNode.interactive(
            id: .root, focusable: true,
            child: Text("3D").frame(maxWidth: .max, maxHeight: .max).render(in: BuildContext().child(0)))
        #expect(region.render(in: BuildContext()) == expected)
    }

    @Test("the hook receives the node id and region id")
    func hookReceivesRegistration() {
        let log = RegionLog()
        let context = BuildContext(registerNativeRegion: { log.entries.append(($0, $1)) })
        _ = NativeRegion(viewport) { Text("3D") }.render(in: context)
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.0 == .root)
        #expect(log.entries.first?.1 == viewport)
    }

    @Test("focusable: false and a disabled environment stay out of focus order")
    func focusableFlags() {
        let off = NativeRegion(viewport, focusable: false) { Text("3D") }.render(in: BuildContext())
        guard case .interactive(_, let focusable, _) = off else { Issue.record("not interactive"); return }
        #expect(focusable == false)
        var env = EnvironmentValues(); env.isEnabled = false
        let disabled = NativeRegion(viewport) { Text("3D") }.render(in: BuildContext(environment: env))
        guard case .interactive(_, let disabledFocusable, _) = disabled else { Issue.record("not interactive"); return }
        #expect(disabledFocusable == false)
    }

    @Test("the fallback paints exactly like the same tree without registration")
    func fallbackPaintParity() {
        let size = Size(width: 20, height: 4)
        let regionNode = NativeRegion(viewport) { Text("3D viewport") }.render(in: BuildContext())
        let plainNode = RenderNode.interactive(
            id: .root, focusable: true,
            child: Text("3D viewport").frame(maxWidth: .max, maxHeight: .max).render(in: BuildContext().child(0)))
        func painted(_ node: RenderNode) -> DrawList {
            var buffer = CellBuffer(size: size)
            CellPainter.paint(LayoutEngine.layout(node, in: Rect(origin: .zero, size: size)), into: &buffer)
            return DrawListSerializer().serialize(buffer)
        }
        #expect(painted(regionNode) == painted(plainNode))
        #expect(painted(regionNode).commands.contains { if case .text(let s, _, _) = $0 { s.contains("3D viewport") } else { false } })
    }

    @Test("MLIR sees no new op: a region lowers exactly as its interactive node")
    func mlirUnchanged() {
        let regionNode = NativeRegion(viewport) { Text("3D") }.render(in: BuildContext())
        let plainNode = RenderNode.interactive(
            id: .root, focusable: true,
            child: Text("3D").frame(maxWidth: .max, maxHeight: .max).render(in: BuildContext().child(0)))
        #expect(GamaLowering.lower(module: regionNode) == GamaLowering.lower(module: plainNode))
    }
}

private struct RegionApp: App {
    let show = Signal(true)
    var scenes: some Scene {
        Window("Regions", id: "main", role: .primary) {
            VStack {
                Button("Top") {}
                if show.get() {
                    NativeRegion(viewport) { Text("3D") }.frame(width: 20, height: 5)
                }
            }
        }
    }
}

private struct DuplicateApp: App {
    var scenes: some Scene {
        Window("Dup", id: "main", role: .primary) {
            VStack {
                NativeRegion(viewport) { Text("A") }.frame(width: 10, height: 2)
                NativeRegion(viewport) { Text("B") }.frame(width: 10, height: 2)
            }
        }
    }
}

@Suite("Native region host table")
struct NativeRegionHostTests {
    private let size = Size(width: 40, height: 10)

    @Test("a registered region is published with its laid-out frame")
    func publishedWithFrame() throws {
        var host = try FrameHost(app: RegionApp())
        _ = host.pump(size: size)
        let regions = host.nativeRegions
        #expect(regions.count == 1)
        #expect(regions.first?.id == viewport)
        #expect(regions.first?.frame.size == Size(width: 20, height: 5))
        #expect((regions.first?.frame.minY ?? 0) >= 1)  // below the button
    }

    @Test("a region absent after a rebuild disappears")
    func disappearsAfterRebuild() throws {
        let app = RegionApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: size)
        app.show.set(false)
        _ = host.pump(size: size)
        let regions = host.nativeRegions
        #expect(regions.isEmpty)
    }

    @Test("isFocused follows host focus")
    func focusTracks() throws {
        var host = try FrameHost(app: RegionApp())
        _ = host.pump(size: size)            // focus lands on the first focusable, the button
        let before = host.nativeRegions
        #expect(before.first?.isFocused == false)
        host.handle(.key(.tab))
        _ = host.pump(size: size)
        let after = host.nativeRegions
        #expect(after.first?.isFocused == true)
    }

    @Test("a duplicate id is reported and the last registration wins")
    func duplicatesReported() throws {
        var host = try FrameHost(app: DuplicateApp())
        _ = host.pump(size: size)
        let regions = host.nativeRegions
        let duplicates = host.duplicateNativeRegionIDs
        #expect(regions.count == 1)
        #expect(duplicates == [viewport])
        #expect((regions.first?.frame.minY ?? 0) >= 2)  // the second, lower region
    }

    @Test("HostPump forwards the host's regions")
    func pumpForwards() throws {
        var pump = HostPump(host: try FrameHost(app: RegionApp()), size: size)
        _ = pump.advance()
        let regions = pump.nativeRegions
        #expect(regions.map(\.id) == [viewport])
    }
}
