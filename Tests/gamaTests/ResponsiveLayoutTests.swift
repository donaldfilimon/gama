//  ResponsiveLayoutTests.swift — layout that adapts to the space it has:
//  `EnvironmentValues.widthClass` at each threshold edge, and
//  `ViewThatFits` choosing the first candidate whose ideal size fits the
//  surface, falling back to the last, without letting losing candidates
//  register actions. Goldens read the painted frame back through
//  `DrawListSerializer` (a `CellSerializer`) and `AccessibilitySnapshot`.

import GamaMacros
import Testing

@testable import GamaCore
@testable import GamaDraw

private func environment(width: Int?) -> EnvironmentValues {
    var env = EnvironmentValues()
    env.surfaceSize = width.map { Size(width: $0, height: 24) }
    return env
}

/// The painted frame of one pump at `size`, as text lines read back from
/// the serialized draw list.
private func frameLines(_ host: inout FrameHost, _ size: Size) -> [String] {
    let laid = host.pump(size: size)
    var buffer = CellBuffer(size: size)
    CellPainter.paint(laid, into: &buffer)
    let list = DrawListSerializer().serialize(buffer)
    return AccessibilitySnapshot.from(list).lines.map(\.text)
}

private let wideLine = "wide " + String(repeating: "=", count: 95)  // 100 columns
private let regularLine = "regular " + String(repeating: "-", count: 62)  // 70 columns

private struct ResponsiveApp: App {
    let presses: Signal<[String]>

    init() { presses = Signal([]) }
    init(presses: Signal<[String]>) { self.presses = presses }

    var scenes: some Scene {
        Window("Responsive", id: "main", role: .primary) {
            ViewThatFits {
                VStack {
                    Text(wideLine)
                    Button(action: { presses.update { $0.append("wide") } }) {
                        Text("wide action")
                    }
                    .actionIdentity(ActionID("wide"))
                }
                VStack {
                    Text(regularLine)
                    Text("second row")
                }
                Button(action: { presses.update { $0.append("compact") } }) {
                    Text("compact")
                }
                .actionIdentity(ActionID("compact"))
            }
        }
    }
}

/// A labelled counter: one `@Reactive` slot and a button that bumps it.
@Component
private struct Tally {
    let label: String
    @Reactive var count: Int = 0

    var body: some View {
        Button("\(label) \(count)") { count += 1 }
    }
}

/// Two candidates that each hold a `@Reactive` counter: the first needs a
/// 100-column surface, the second fits anywhere.
private struct TallyApp: App {
    var scenes: some Scene {
        Window("Tallies", id: "main", role: .primary) {
            ViewThatFits {
                VStack(spacing: 0) {
                    Text(wideLine)
                    Tally(label: "wide")
                }
                Tally(label: "narrow")
            }
        }
    }
}

/// A candidate whose ideal width grows with its own state: 10 columns plus
/// 20 per press, so the second press pushes it past a 40-column surface.
@Component
private struct Grower {
    @Reactive var count: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Text(String(repeating: "#", count: 10 + 20 * count))
            Button("grow") { count += 1 }
        }
    }
}

private struct GrowerApp: App {
    var scenes: some Scene {
        Window("Grower", id: "main", role: .primary) {
            ViewThatFits {
                Grower()
                Text("fallback")
            }
        }
    }
}

@Suite("Responsive layout")
struct ResponsiveLayoutTests {
    @Test("widthClass changes class exactly at its public thresholds")
    func widthClassThresholds() {
        #expect(WidthClass.regularMinimumWidth == 60)
        #expect(WidthClass.wideMinimumWidth == 120)
        #expect(environment(width: 59).widthClass == .compact)
        #expect(environment(width: 60).widthClass == .regular)
        #expect(environment(width: 119).widthClass == .regular)
        #expect(environment(width: 120).widthClass == .wide)
        #expect(environment(width: 1).widthClass == .compact)
    }

    @Test("widthClass is nil without a surface")
    func widthClassWithoutSurface() {
        #expect(environment(width: nil).widthClass == nil)
    }

    @Test("the host's surface drives widthClass during the build")
    func widthClassFollowsTheHost() throws {
        struct ClassProbe: View {
            typealias Body = Never_
            var body: Never_ { Never_() }
            func render(in context: BuildContext) -> RenderNode {
                let name: String
                switch context.environment.widthClass {
                case .compact: name = "compact"
                case .regular: name = "regular"
                case .wide: name = "wide"
                case nil: name = "none"
                }
                return Text("class \(name)").render(in: context)
            }
        }
        struct ProbeApp: App {
            var scenes: some Scene {
                Window("Probe", id: "main", role: .primary) { ClassProbe() }
            }
        }
        var host = try FrameHost(app: ProbeApp())
        #expect(frameLines(&host, Size(width: 40, height: 3)).first == "class compact")
        #expect(frameLines(&host, Size(width: 80, height: 3)).first == "class regular")
        #expect(frameLines(&host, Size(width: 120, height: 3)).first == "class wide")
    }

    @Test("ViewThatFits picks the first candidate that fits, per surface")
    func picksFirstThatFits() throws {
        var host = try FrameHost(app: ResponsiveApp())
        let wide = frameLines(&host, Size(width: 120, height: 40))
        #expect(wide.first == wideLine)
        #expect(wide.contains { $0.contains("wide action") })

        let regular = frameLines(&host, Size(width: 80, height: 24))
        #expect(regular.first == regularLine)
        #expect(regular.contains("second row"))

        let compact = frameLines(&host, Size(width: 40, height: 20))
        #expect(compact.first?.contains("compact") == true)
        #expect(!compact.contains { $0.contains("regular") || $0.contains("wide") })
    }

    @Test("ViewThatFits falls back to the last candidate when none fits")
    func fallsBackToTheLast() throws {
        var host = try FrameHost(app: ResponsiveApp())
        let lines = frameLines(&host, Size(width: 4, height: 1))
        #expect(lines.first == "comp")
    }

    @Test("losing candidates register no actions")
    func losersRegisterNothing() throws {
        let presses = Signal<[String]>([])
        var host = try FrameHost(app: ResponsiveApp(presses: presses))
        _ = host.pump(size: Size(width: 40, height: 20))
        host.perform(ActionID("wide"))
        host.perform(ActionID("compact"))
        #expect(presses.get() == ["compact"])

        _ = host.pump(size: Size(width: 120, height: 40))
        host.perform(ActionID("wide"))
        host.perform(ActionID("compact"))
        #expect(presses.get() == ["compact", "wide"])
    }

    @Test("every candidate's @Reactive state stays live, whichever one renders")
    func everyCandidateKeepsItsState() throws {
        var host = try FrameHost(app: TallyApp())
        _ = frameLines(&host, Size(width: 120, height: 40))
        let liveWhenWide = host.reactiveStateCount
        #expect(liveWhenWide == 2)
        _ = frameLines(&host, Size(width: 40, height: 20))
        let liveWhenCompact = host.reactiveStateCount
        #expect(liveWhenCompact == 2)
    }

    @Test("a counter survives a switch away and back, in both directions")
    func stateSurvivesSwitchesBothWays() throws {
        let wide = Size(width: 120, height: 40)
        let compact = Size(width: 40, height: 20)
        var host = try FrameHost(app: TallyApp())

        // The narrow candidate renders after the wide one in the list.
        _ = frameLines(&host, compact)
        host.handle(.key(.enter))
        #expect(frameLines(&host, compact).contains { $0.contains("narrow 1") })
        #expect(frameLines(&host, wide).contains { $0.contains("wide 0") })
        #expect(frameLines(&host, compact).contains { $0.contains("narrow 1") })

        // The wide candidate renders before the narrow one.
        _ = frameLines(&host, wide)
        host.handle(.key(.enter))
        host.handle(.key(.enter))
        #expect(frameLines(&host, wide).contains { $0.contains("wide 2") })
        #expect(frameLines(&host, compact).contains { $0.contains("narrow 1") })
        #expect(frameLines(&host, wide).contains { $0.contains("wide 2") })
    }

    @Test("a candidate its own state pushed out of fitting stays out")
    func stateDrivenRejectionIsStable() throws {
        let size = Size(width: 40, height: 10)
        var host = try FrameHost(app: GrowerApp())
        #expect(frameLines(&host, size).contains { $0.contains("grow") })
        host.handle(.key(.enter))
        #expect(frameLines(&host, size).contains { $0.contains("grow") })
        host.handle(.key(.enter))
        // Thirty columns became fifty: measured with the live count, the
        // grower no longer fits and the fallback renders.
        #expect(frameLines(&host, size) == ["fallback"])
        // Its state was kept, so it does not snap back on the next frame.
        host.invalidate()
        #expect(frameLines(&host, size) == ["fallback"])
    }

    @Test("host-less rendering has no surface, so the first candidate renders")
    func hostlessRendersFirst() {
        let node = ViewThatFits {
            Text("first")
            Text("second")
        }.render(in: BuildContext())
        #expect(node == .text("first", style: .plain))
    }

    @Test("goldens at 120x40, 80x24 and 40x20")
    func goldens() throws {
        var host = try FrameHost(app: ResponsiveApp())
        #expect(frameLines(&host, Size(width: 120, height: 40)) == [wideLine, "wide action"])
        #expect(frameLines(&host, Size(width: 80, height: 24)) == [regularLine, "second row"])
        #expect(frameLines(&host, Size(width: 40, height: 20)) == ["compact"])
    }
}
