//  SignalTests.swift — reactive signal observation.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

@Suite("Signal")
struct SignalTests {
    @Test("observe and cancel")
    func observeAndCancel() {
        let s = Signal(0)
        let hits = TestBox(0)
        let token = s.observe { hits.value += 1 }
        s.set(1)
        #expect(hits.value == 1)
        s.cancel(token)
        s.set(2)
        #expect(hits.value == 1)
        #expect(s.get() == 2)
    }

    @Test("host-owned subscription invalidates and cancels in isolation")
    func hostOwnedSubscriptionInvalidatesAndCancelsInIsolation() throws {
        struct StaticApp: App {
            var scenes: some Scene {
                Window("Model", id: "main", role: .primary) { Text("model") }
            }
        }
        let model = Signal(0)
        var first = try FrameHost(app: StaticApp())
        var second = try FrameHost(app: StaticApp())
        first.observe(model)
        first.observe(model)
        second.observe(model)
        _ = first.pump(size: Size(width: 10, height: 1))
        _ = second.pump(size: Size(width: 10, height: 1))
        // Bind before #expect: the macro's property-access form needs a
        // Copyable base, and FrameHost is deliberately noncopyable.
        let pumpedStates = (first.needsFrame, second.needsFrame)
        #expect(!pumpedStates.0)
        #expect(!pumpedStates.1)

        first.cancelSubscriptions()
        model.set(1)
        let cancelledStates = (first.needsFrame, second.needsFrame)
        #expect(!cancelledStates.0)
        #expect(cancelledStates.1)
    }

    @Test("binding can receive explicit subscription context")
    func bindingCanReceiveExplicitSubscriptionContext() {
        let model = Signal(1)
        let invalidations = TestBox(0)
        let context = SubscriptionContext { invalidations.value += 1 }
        let binding = model.binding(in: context)
        binding.wrappedValue = 2
        #expect(invalidations.value == 1)
        #expect(model.get() == 2)
        context.cancelAll()
        model.set(3)
        #expect(invalidations.value == 1)
    }

    @Test("reentrant set does not reenter observers")
    func reentrantSetDoesNotReenterObservers() {
        let s = Signal(0)
        let hits = TestBox(0)
        let token = s.observe {
            hits.value += 1
            if s.get() == 1 { s.set(2) }
        }
        s.set(1)
        #expect(hits.value == 1)
        #expect(s.get() == 2)
        s.cancel(token)
    }

    @Test("observer added during notify defers to next change")
    func observerAddedDuringNotifyDefersToNextChange() {
        let s = Signal(0)
        let lateHits = TestBox(0)
        let added = TestBox(false)
        let token = s.observe {
            if !added.value {
                added.value = true
                s.observe { lateHits.value += 1 }
            }
        }
        s.set(1)
        #expect(lateHits.value == 0)
        s.set(2)
        #expect(lateHits.value == 1)
        s.cancel(token)
    }

    @Test("setIfChanged skips redundant notifies")
    func setIfChangedSkipsRedundantNotifies() {
        let s = Signal(7)
        let hits = TestBox(0)
        s.observe { hits.value += 1 }
        s.setIfChanged(7)
        #expect(hits.value == 0)
        s.setIfChanged(8)
        #expect(hits.value == 1)
    }

    @Test("binding reads and writes through Signal")
    func bindingReadsAndWritesThroughSignal() {
        let s = Signal(1)
        let b = s.binding()
        #expect(b.wrappedValue == 1)
        b.wrappedValue = 5
        #expect(s.get() == 5)

        let doubled = b.map(get: { $0 * 2 }, set: { v, new in v = new / 2 })
        #expect(doubled.wrappedValue == 10)
        doubled.wrappedValue = 8
        #expect(s.get() == 4)
    }

    @Test("signal routes changes to explicit observer")
    func signalRoutesChangesToExplicitObserver() {
        let fired = TestBox(0)
        let s = Signal("a")
        s.observe { fired.value += 1 }
        s.set("b")
        #expect(fired.value == 1)
    }

    @Test("concurrent hosts remain isolated")
    func concurrentHostsRemainIsolated() async throws {
        struct ConcurrentApp: App {
            let count: Signal<Int>
            init() { count = Signal(0) }
            init(count: Signal<Int>) { self.count = count }
            var scenes: some Scene {
                Window("Concurrent", id: "main", role: .primary) {
                    Button("increment") { count.update { $0 += 1 } }
                }
            }
        }

        let results = try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let count = Signal(0)
                    var host = try FrameHost(app: ConcurrentApp(count: count))
                    _ = host.pump(size: Size(width: 20, height: 2))
                    host.handle(.key(.enter))
                    _ = host.pump(size: Size(width: 20, height: 2))
                    return count.get()
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(results.count == 16)
        #expect(results.allSatisfy { $0 == 1 })
    }
}
