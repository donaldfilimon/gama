//  main.swift — GamaBench (gama-bench)
//  The deterministic measurement harness the roadmap requires *before* any
//  frame-path optimization, and the same scenario Task 5's Instruments pass
//  drives. It measures; it never asserts a threshold, so it is not a gate and
//  cannot fail a build on a noisy machine.
//
//  Usage:  gama-bench [--runs N] [--frames N] [--warmup N]
//
//  Scenario (fixed, so two invocations are comparable):
//   • a fixed 80x24 render loop over a representative tree
//   • a 160x48 <-> 80x24 resize loop
//   • a deterministic key/pointer script, replayed identically every run
//
//  Reported per phase: median and p95 nanoseconds per iteration, taken over
//  every iteration of every run. Process peak resident memory and live-heap
//  growth are reported once, at the end.
//
//  Deliberately NOT reported: allocation *count*. Nothing available to a
//  plain process on Darwin counts allocations cumulatively — `malloc_zone`
//  statistics describe live blocks, not lifetime allocations — so claiming a
//  count here would be inventing a number. Allocation counts come from
//  Instruments' Allocations template, which is Task 5's tool.

import GamaCore
import GamaDraw

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif os(Windows)
    // `exit` lives in the C runtime. Before InternalImportsByDefault it
    // leaked into this file through another module's import; now every
    // module's imports are internal, so the bench names its own.
    #if canImport(CRT)
        import CRT
    #elseif canImport(ucrt)
        import ucrt
    #endif
    import WinSDK
#endif

// MARK: Scenario

/// A tree deliberately larger and more varied than a smoke app: nested
/// stacks, borders, backgrounds, per-row style changes, and focusable
/// controls, so `presentDiff` sees many style runs and `forEachRun` sees
/// many short runs rather than one long default one.
private struct BenchApp: App {
    var scenes: some Scene {
        Window("Bench", id: "main", role: .primary) {
            VStack(spacing: 0) {
                Text("Gama benchmark surface")
                    .bold()
                    .foregroundColor(Color(r: 200, g: 220, b: 255))
                HStack(spacing: 1) {
                    VStack(spacing: 0) {
                        Text("alpha").foregroundColor(Color(r: 255, g: 80, b: 80))
                        Text("bravo").foregroundColor(Color(r: 80, g: 255, b: 80))
                        Text("charlie").foregroundColor(Color(r: 80, g: 80, b: 255))
                        Text("delta").italic()
                        Text("echo").underline()
                    }
                    .border(.rounded, title: "left")
                    VStack(spacing: 0) {
                        Button("First action") {}
                        Button("Second action") {}
                        Button("Third action") {}
                        Text("status: idle").foregroundColor(Color(r: 120, g: 120, b: 120))
                    }
                    .border(.single, title: "right")
                }
                Text("footer row with a longer stretch of plain text to merge")
                    .background(Color(r: 20, g: 20, b: 40))
            }
        }
    }
}

/// One cycle of the input script. Replayed in order and wrapped modulo its
/// length, so frame *n* always receives the same event on every run and on
/// every machine.
private let inputScript: [InputEvent] = [
    .key(.tab),
    .key(.tab),
    .key(.enter),
    .pointer(Point(x: 12, y: 4), pressed: true),
    .pointer(Point(x: 12, y: 4), pressed: false),
    .key(.backTab),
    .key(.character("x")),
    .key(.escape),
]

// MARK: Statistics

/// Per-iteration nanosecond samples for one measured phase.
private struct Samples {
    let name: String
    var values: [Int64] = []

    mutating func record(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        values.append(seconds &* 1_000_000_000 &+ attoseconds / 1_000_000_000)
    }

    /// Median and p95, both by nearest-rank on the sorted samples. Nearest
    /// rank rather than interpolation: an interpolated p95 invents a value
    /// no iteration actually took.
    var summary: (median: Int64, p95: Int64, count: Int) {
        guard !values.isEmpty else { return (0, 0, 0) }
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p95Index = min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
        return (median, sorted[max(0, p95Index)], sorted.count)
    }
}

// MARK: Memory

/// Peak resident bytes for this process, or `nil` where the platform offers
/// no cheap way to ask. Reported rather than asserted.
private func peakResidentBytes() -> UInt64? {
    #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size_max : nil
    #else
        return nil
    #endif
}

/// Bytes currently live in the default malloc zone. The delta across the run
/// is heap *growth*, not allocation volume; the header explains why the
/// stronger number is deliberately absent.
private func liveHeapBytes() -> UInt64? {
    #if canImport(Darwin)
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(malloc_default_zone(), &statistics)
        return UInt64(statistics.size_in_use)
    #else
        return nil
    #endif
}

// MARK: Harness

private struct Options {
    var runs = 5
    var frames = 2_000
    var warmup = 200
}

private func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = arguments.next() {
        switch argument {
        case "--runs": options.runs = Int(arguments.next() ?? "") ?? options.runs
        case "--frames": options.frames = Int(arguments.next() ?? "") ?? options.frames
        case "--warmup": options.warmup = Int(arguments.next() ?? "") ?? options.warmup
        case "--help", "-h":
            print("usage: gama-bench [--runs N] [--frames N] [--warmup N]")
            exit(0)
        default:
            FileHandleStandardError.write("gama-bench: unknown argument \(argument)\n")
            exit(64)
        }
    }
    return options
}

/// Minimal stderr writer; the harness pulls in no Foundation.
private enum FileHandleStandardError {
    static func write(_ message: String) {
        for byte in Array(message.utf8) {
            _ = fputc(Int32(byte), stderr)
        }
    }
}

private let fixedSize = Size(width: 80, height: 24)
private let grownSize = Size(width: 160, height: 48)

private func run() throws {
    let options = parseOptions()
    let clock = ContinuousClock()

    var paint = Samples(name: "paint (pump + clearBack + CellPainter)")
    var diff = Samples(name: "presentDiff (ANSI diff, 80x24)")
    var runs = Samples(name: "forEachRun via DrawList.from (80x24)")
    var resize = Samples(name: "resize loop (80x24 <-> 160x48, painted)")

    let heapBefore = liveHeapBytes()

    for _ in 0..<options.runs {
        var host = try FrameHost(app: BenchApp())
        var buffer = CellBuffer(size: fixedSize)
        host.handle(.lifecycle(.didLaunch))

        // Warm-up frames are executed but not recorded: the first frames pay
        // for lazy metadata, first-touch pages, and buffer growth, and folding
        // that into the median would flatter any later change.
        for frame in 0..<(options.warmup + options.frames) {
            host.handle(inputScript[frame % inputScript.count])
            let record = frame >= options.warmup

            let laidOut: LaidOutNode
            if record {
                let start = clock.now
                let node = host.pump(size: fixedSize)
                buffer.clearBack()
                CellPainter.paint(node, into: &buffer)
                paint.record(clock.now - start)
                laidOut = node
            } else {
                laidOut = host.pump(size: fixedSize)
                buffer.clearBack()
                CellPainter.paint(laidOut, into: &buffer)
            }
            _ = laidOut

            if record {
                let start = clock.now
                let list = DrawList.from(buffer)
                runs.record(clock.now - start)
                blackHole(list.commands.count)
            } else {
                blackHole(DrawList.from(buffer).commands.count)
            }

            if record {
                let start = clock.now
                let ansi = buffer.presentDiff()
                diff.record(clock.now - start)
                blackHole(ansi.utf8.count)
            } else {
                blackHole(buffer.presentDiff().utf8.count)
            }
        }

        // Resize phase: alternate extents so every iteration really changes
        // the grid, and paint at the new extent so the measurement includes
        // the forced full present a resize implies.
        for iteration in 0..<max(1, options.frames / 20) {
            let target = iteration.isMultiple(of: 2) ? grownSize : fixedSize
            let start = clock.now
            buffer.resizeIfNeeded(target)
            let node = host.pump(size: target)
            buffer.clearBack()
            CellPainter.paint(node, into: &buffer)
            blackHole(buffer.presentDiff().utf8.count)
            resize.record(clock.now - start)
        }

        host.cancelSubscriptions()
        host.handle(.lifecycle(.willTerminate))
    }

    report([paint, runs, diff, resize], options: options, heapBefore: heapBefore)
}

/// Keeps a measured result observably used so the optimizer cannot delete the
/// work being timed.
@inline(never)
private func blackHole(_ value: Int) {
    if value == Int.min { FileHandleStandardError.write("") }
}

private func report(_ phases: [Samples], options: Options, heapBefore: UInt64?) {
    print("gama-bench — runs=\(options.runs) frames=\(options.frames) warmup=\(options.warmup)")
    print("grid: fixed \(fixedSize.width)x\(fixedSize.height), grown \(grownSize.width)x\(grownSize.height)")
    print("")
    print("phase                                            samples   median ns      p95 ns")
    for phase in phases {
        let (median, p95, count) = phase.summary
        let name = padRight(phase.name, 46)
        print("\(name)  \(pad(count, 7))  \(pad(median, 10))  \(pad(p95, 10))")
    }
    print("")
    if let peak = peakResidentBytes() {
        print("peak resident: \(peak) bytes (\(peak / 1024) KiB)")
    } else {
        print("peak resident: unavailable on this platform")
    }
    if let before = heapBefore, let after = liveHeapBytes() {
        let growth = Int64(bitPattern: after) - Int64(bitPattern: before)
        print("live heap growth: \(growth) bytes (live bytes, NOT an allocation count)")
    } else {
        print("live heap growth: unavailable on this platform")
    }
    print("")
    // One machine-readable line per phase, so a before/after comparison is a
    // diff rather than a re-reading of the table.
    for phase in phases {
        let (median, p95, count) = phase.summary
        print("BENCH\t\(phase.name)\t\(count)\t\(median)\t\(p95)")
    }
}

private func padRight(_ text: String, _ width: Int) -> String {
    guard text.count < width else { return text }
    return text + String(repeating: " ", count: width - text.count)
}

private func pad(_ value: some BinaryInteger, _ width: Int) -> String {
    let text = String(value)
    guard text.count < width else { return text }
    return String(repeating: " ", count: width - text.count) + text
}

do {
    try run()
} catch {
    FileHandleStandardError.write("gama-bench: \(error)\n")
    exit(70)
}
