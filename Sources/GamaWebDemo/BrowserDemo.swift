import GamaCore

// The browser demo is deliberately macro-free: `GamaMacros` is a host-side
// compiler plugin, so `GamaWebDemo` must not pull it into the wasm32
// dependency graph (ADR 0011, `docs/backends/WASM.md`). Every `@Component`
// and `@Reactive` affordance below is therefore written out by hand, and
// `#rgb` is replaced by a plain `Color` initializer.

private let accent = Color(r: 0xFF, g: 0x88, b: 0x00)
private let teal = Color(r: 0x34, g: 0xC9, b: 0xB0)
private let muted = Color(r: 0x8A, g: 0x8F, b: 0x98)

/// The demo surface: stats, a command row, text entry, a toggle, progress,
/// and a feature list, all painted through the same `CellBuffer` the TUI and
/// Apple backends use.
///
/// Four details are load-bearing for the two smoke drivers and must survive
/// any edit to this layout. The first two were found by breaking them:
///
/// * **`count <n>` has to be one `Text`.** `scripts/wasm-runtime-smoke.mjs`
///   runs its `/\bcount ([0-9]+)\b/` against the raw HTML, where each styled
///   run is its own `<span>`. Splitting the label and the value into two
///   `Text`s puts a tag between them and the match silently disappears —
///   `scripts/browser-runtime-smoke.mjs` does not catch it, because it reads
///   `textContent`, which concatenates spans.
/// * **The layout has to degrade to a 40x8 grid.** That is the size the
///   headless driver resizes to, and it reads the *painted* output, so the
///   count line must still be on screen there: two border rows leave six
///   content rows, and this stack puts the count on the third.
/// * The outermost modifier is `.border(…)`, so grid column 0 is border on
///   every row and the smoke's pointer press cannot land on a control. That
///   press is what proves a non-activating event leaves state alone.
/// * The first two controls in tab order each take `count` from 0 to exactly
///   1. Focus starts on the first focusable and both drivers send Tab before
///   Enter, so either one satisfies the pinned `0 -> 1` transition and the
///   assertion does not depend on which.
struct WebDemoPanel: View {
    private let count = ReactiveSlot(0)
    private let step = ReactiveSlot(1)
    private let name = ReactiveSlot("")
    private let notifications = ReactiveSlot(true)

    var body: some View {
        let n = count.get()
        let s = step.get()
        let who = name.get()
        let notify = notifications.get()

        return VStack(alignment: .leading, spacing: 0) {
            Text("Gama Web").bold().foregroundColor(accent)
            Text("one retained pipeline · Swift 6").italic().foregroundColor(muted)

            HStack(spacing: 3) {
                // One Text, therefore one span: see the note above.
                Text("count \(n)").bold().foregroundColor(teal)
                Text("step \(s)").foregroundColor(muted)
                Text(notify ? "notify on" : "notify off")
                    .foregroundColor(notify ? teal : muted)
            }

            HStack(spacing: 2) {
                Button("+1") { count.set(count.get() + 1) }
                Button("+step") { count.set(count.get() + step.get()) }
                Button("step ×2") { step.set(step.get() * 2) }
                Button("reset") {
                    count.set(0)
                    step.set(1)
                }
                // Clamped at zero so the rendered count is always a
                // non-negative integer, whatever order these are pressed in —
                // both drivers match `count` with `[0-9]+`.
                Button("−step") { count.set(max(0, count.get() - step.get())) }
                    .disabled(n == 0)
            }

            Divider()
            HStack(spacing: 2) {
                TextField("your name", text: name.binding())
                Toggle("notifications", isOn: notifications.binding())
            }
            Text(who.isEmpty ? "hello, stranger" : "hello, \(who)")
                .foregroundColor(muted)
            ProgressView(
                value: Double(min(n, 10)), total: 10,
                label: "activity", width: 24)

            Divider()
            List {
                Text("• one CellBuffer painted by TUI, Apple, and this page")
                Text("• styled spans, Unicode-aware cells, run-merged output")
                Text("• per-surface @Reactive state, written out by hand here")
            }
            Text("Tab / Shift-Tab focus · Enter or Space press · click works")
                .foregroundColor(muted)
        }
        // Horizontal padding only: two vertical cells are worth more as
        // content at the 40x8 size the headless driver pins.
        .padding(EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
        .border(.rounded, color: accent, title: "gama web demo")
    }

    /// Matches `@Component`'s expansion: bind every slot against this
    /// component's identity before evaluating `body`, so a fresh instance
    /// each frame reads the host's storage rather than its own (ADR 0011).
    /// Slot indices are declaration order and must not be reordered — they
    /// are half of the storage key.
    func render(in context: BuildContext) -> RenderNode {
        count._bind(in: context, slot: 0)
        step._bind(in: context, slot: 1)
        name._bind(in: context, slot: 2)
        notifications._bind(in: context, slot: 3)
        return body.render(in: context.child(0))
    }
}

struct BrowserDemo: App {
    init() {}
    var scenes: some Scene {
        Window("Gama Web", id: "main", role: .primary) { WebDemoPanel() }
    }
}
