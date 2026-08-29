//  Scenario.swift — GamaAppleDemo
//  The deterministic, non-interactive profiling scenario Roadmap Task 5
//  requires *before* the six-way Apple-host split, so the split can be
//  measured against something that already exists.
//
//  Usage:  gama-apple-demo --scenario [--frames N] [--warmup N]
//
//  It replays `gama-bench`'s scenario through the *native* host instead of
//  through GamaCore/GamaDraw alone: the same 80x24 tree, the same eight-event
//  input script, the same 80x24 <-> 160x48 resize loop — but every frame is
//  pumped through `GamaHostView` and rasterized through CoreGraphics, so the
//  paths Task 5 names (CoreGraphics replay, font selection, attributed-string
//  creation, dirty-rect handling) are inside the measurement.
//
//  It measures; it asserts no threshold, so it is not a gate.
//
//  Determinism is *reported*, not claimed: a running digest over every
//  frame's draw-command count and a digest of the final rasterized bitmap
//  are printed, so two runs can be compared byte-for-byte rather than
//  trusted.

#if canImport(AppKit)

    import AppKit
    import GamaAppleShell
    import GamaAppleUI
    import GamaCore
    import GamaDraw

    // MARK: Scenario app

    /// Mirrors `GamaBench`'s `BenchApp` tree — nested stacks, borders,
    /// per-row style changes, focusable controls, and a background fill — so
    /// the native host renders the same surface the portable harness does.
    /// Every button action is a no-op, which is what makes the shared input
    /// script (which includes `.enter` and a pointer press) safe to replay
    /// thousands of times without opening windows or otherwise drifting.
    private struct ScenarioApp: App {
        var scenes: some Scene {
            Window("Gama scenario", id: "main", role: .primary,
                initialCellSize: Size(width: 80, height: 24)
            ) {
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

    /// One cycle of the input script, byte-identical to `gama-bench`'s.
    /// Replayed in order and wrapped modulo its length, so frame *n* receives
    /// the same event on every run and on every machine.
    private let scenarioInputScript: [InputEvent] = [
        .key(.tab),
        .key(.tab),
        .key(.enter),
        .pointer(Point(x: 12, y: 4), pressed: true),
        .pointer(Point(x: 12, y: 4), pressed: false),
        .key(.backTab),
        .key(.character("x")),
        .key(.escape),
    ]

    private let scenarioFixedSize = Size(width: 80, height: 24)
    private let scenarioGrownSize = Size(width: 160, height: 48)

    // MARK: Statistics

    /// Per-iteration nanosecond samples for one measured phase. Median and
    /// p95 are nearest-rank on the sorted samples, matching `gama-bench`:
    /// an interpolated p95 would invent a value no iteration actually took.
    private struct ScenarioSamples {
        let name: String
        var values: [Int64] = []

        mutating func record(_ duration: Duration) {
            let (seconds, attoseconds) = duration.components
            values.append(seconds &* 1_000_000_000 &+ attoseconds / 1_000_000_000)
        }

        var summary: (median: Int64, p95: Int64, count: Int) {
            guard !values.isEmpty else { return (0, 0, 0) }
            let sorted = values.sorted()
            let median = sorted[sorted.count / 2]
            let index = min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
            return (median, sorted[max(0, index)], sorted.count)
        }
    }

    /// FNV-1a, 64-bit. Used only as a cheap determinism witness — two runs
    /// that print the same digests rendered the same frames.
    private struct FNV1a {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func combine(_ byte: UInt8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }

        mutating func combine(_ number: Int) {
            withUnsafeBytes(of: UInt64(bitPattern: Int64(number)).littleEndian) { bytes in
                for byte in bytes { combine(byte) }
            }
        }

        mutating func combine(_ buffer: UnsafeBufferPointer<UInt8>) {
            for byte in buffer { combine(byte) }
        }
    }

    // MARK: Memory

    /// Peak resident bytes for this process. Reported, never asserted.
    private func scenarioPeakResidentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size_max : nil
    }

    /// Bytes currently live in the default malloc zone. The delta across the
    /// run is heap *growth*, not allocation volume — `malloc_zone` statistics
    /// describe live blocks, not lifetime allocations. Allocation counts come
    /// from Instruments' Allocations template, never from here.
    private func scenarioLiveHeapBytes() -> UInt64 {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(malloc_default_zone(), &statistics)
        return UInt64(statistics.size_in_use)
    }

    // MARK: Options

    private struct ScenarioOptions {
        // Deliberately below gama-bench's 2000/200: on current main the
        // native host aborts inside CoreText after a few hundred frames
        // (docs/Performance.md). The harness imposes no limit of its own.
        var frames = 150
        var warmup = 30
    }

    private func parseScenarioOptions() -> ScenarioOptions {
        var options = ScenarioOptions()
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--scenario": continue
            case "--frames": options.frames = Int(arguments.next() ?? "") ?? options.frames
            case "--warmup": options.warmup = Int(arguments.next() ?? "") ?? options.warmup
            default:
                FileHandle.standardError.write(
                    Data("gama-apple-demo --scenario: unknown argument \(argument)\n".utf8))
                exit(64)
            }
        }
        return options
    }

    // MARK: Harness

    /// Boots `NSApplication` offscreen — accessory activation policy,
    /// `finishLaunching()` without entering the event loop — hosts the
    /// primary scene through the same `GamaShellCoordinator` the shell uses,
    /// then replays the fixed input and resize scripts, rasterizing every
    /// frame through `GamaHostView.draw(_:)` via `cacheDisplay(in:to:)`.
    ///
    /// No run loop means no timers, no user input, and no display-link
    /// pacing: every frame is driven synchronously by this function, which
    /// is what makes the measurement reproducible.
    @MainActor
    func runAppleHostScenario() throws(SceneConfigurationError) -> Never {
        let options = parseScenarioOptions()
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()

        // Replicates `GamaHostView.commonInit`'s measurement exactly; the
        // view's own `cellSize` is internal to GamaAppleUI, so the scenario
        // re-measures rather than reaching for it.
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let probe = NSAttributedString(string: "M", attributes: [.font: font]).size()
        let cell = CGSize(width: ceil(probe.width), height: ceil(probe.height))
        guard cell.width > 0, cell.height > 0 else {
            print("error: scenario measured a zero-sized monospaced cell")
            exit(1)
        }

        let graph = try compileSceneGraph(ScenarioApp())
        let coordinator = GamaShellCoordinator(graph: graph, presentsWindows: false)
        coordinator.beginApplication()
        guard let instance = coordinator.liveInstanceIDs.first,
            let controller = coordinator.controllers[instance],
            let window = controller.window
        else {
            print("error: scenario opened no primary window instance")
            exit(1)
        }
        let view = controller.hostView

        /// Forces the host onto an exact cell grid and pumps the resulting
        /// layout pass. Fails loudly rather than measuring the wrong extent.
        func setGrid(_ size: Size) {
            let pixels = NSSize(
                width: cell.width * CGFloat(size.width),
                height: cell.height * CGFloat(size.height))
            window.setContentSize(pixels)
            view.frame = NSRect(origin: .zero, size: pixels)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            guard view.currentDrawList.size == size else {
                print(
                    "error: scenario grid is \(view.currentDrawList.size.width)x"
                        + "\(view.currentDrawList.size.height), expected "
                        + "\(size.width)x\(size.height)")
                exit(1)
            }
        }

        setGrid(scenarioFixedSize)
        let fixedBounds = view.bounds
        guard let fixedRep = view.bitmapImageRepForCachingDisplay(in: fixedBounds) else {
            print("error: scenario could not create a caching bitmap representation")
            exit(1)
        }
        setGrid(scenarioGrownSize)
        let grownBounds = view.bounds
        guard let grownRep = view.bitmapImageRepForCachingDisplay(in: grownBounds) else {
            print("error: scenario could not create a caching bitmap representation")
            exit(1)
        }
        setGrid(scenarioFixedSize)

        var event = ScenarioSamples(name: "event + pump (FrameHost -> DrawList.from)")
        var draw = ScenarioSamples(name: "draw (CoreGraphics replay, 80x24)")
        var resize = ScenarioSamples(name: "resize (layout + pump + draw)")
        var frameDigest = FNV1a()
        let clock = ContinuousClock()
        let heapBefore = scenarioLiveHeapBytes()

        for frame in 0..<(options.warmup + options.frames) {
            let scripted = scenarioInputScript[frame % scenarioInputScript.count]
            let record = frame >= options.warmup

            // Each phase drains its own autorelease pool inside its own timed
            // region. There is no run loop here, so nothing else would drain
            // one, and the pool would otherwise grow for the whole run.
            // Draining inside the measurement is also the faithful
            // attribution: the objects released are the ones the measured
            // phase created. (A real app drains per event-loop cycle
            // instead, which distributes the same cost differently. This is
            // *not* what causes the CoreText abort documented in
            // docs/Performance.md — that reproduces with or without pools.)
            if record {
                let start = clock.now
                autoreleasepool { view.send(scripted) }
                event.record(clock.now - start)
            } else {
                autoreleasepool { view.send(scripted) }
            }

            if record {
                let start = clock.now
                autoreleasepool { view.cacheDisplay(in: fixedBounds, to: fixedRep) }
                draw.record(clock.now - start)
            } else {
                autoreleasepool { view.cacheDisplay(in: fixedBounds, to: fixedRep) }
            }

            // Outside every timed region: the digest is evidence, not a
            // measured phase, and must not appear in any phase's numbers.
            frameDigest.combine(view.currentDrawList.commands.count)
        }

        // Alternating extents, so every iteration really changes the grid and
        // the forced full redraw a resize implies is inside the measurement.
        for iteration in 0..<max(1, options.frames / 20) {
            let grown = iteration.isMultiple(of: 2)
            let start = clock.now
            autoreleasepool {
                let pixels = NSSize(
                    width: cell.width
                        * CGFloat(grown ? scenarioGrownSize.width : scenarioFixedSize.width),
                    height: cell.height
                        * CGFloat(grown ? scenarioGrownSize.height : scenarioFixedSize.height))
                window.setContentSize(pixels)
                view.frame = NSRect(origin: .zero, size: pixels)
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
                if grown {
                    view.cacheDisplay(in: grownBounds, to: grownRep)
                } else {
                    view.cacheDisplay(in: fixedBounds, to: fixedRep)
                }
            }
            resize.record(clock.now - start)
            frameDigest.combine(view.currentDrawList.commands.count)
        }

        // Final rasterized bitmap, hashed once and outside every timed
        // region. Same-machine, same-OS evidence only: glyph rasterization
        // differs across OS versions and backing scale factors.
        setGrid(scenarioFixedSize)
        view.cacheDisplay(in: fixedBounds, to: fixedRep)
        var bitmapDigest = FNV1a()
        if let data = fixedRep.bitmapData {
            let count = fixedRep.bytesPerRow * fixedRep.pixelsHigh
            bitmapDigest.combine(UnsafeBufferPointer(start: data, count: count))
        }

        let heapAfter = scenarioLiveHeapBytes()
        reportScenario(
            [event, draw, resize],
            options: options,
            cell: cell,
            rep: fixedRep,
            scale: window.backingScaleFactor,
            commandCount: view.currentDrawList.commands.count,
            frameDigest: frameDigest.value,
            bitmapDigest: bitmapDigest.value,
            heapGrowth: Int64(bitPattern: heapAfter) - Int64(bitPattern: heapBefore))

        coordinator.emitTerminationIfNeeded()
        exit(0)
    }

    private func reportScenario(
        _ phases: [ScenarioSamples],
        options: ScenarioOptions,
        cell: CGSize,
        rep: NSBitmapImageRep,
        scale: CGFloat,
        commandCount: Int,
        frameDigest: UInt64,
        bitmapDigest: UInt64,
        heapGrowth: Int64
    ) {
        print("gama-apple-demo --scenario — frames=\(options.frames) warmup=\(options.warmup)")
        print(
            "grid: fixed \(scenarioFixedSize.width)x\(scenarioFixedSize.height), "
                + "grown \(scenarioGrownSize.width)x\(scenarioGrownSize.height)")
        print(
            "cell: \(Int(cell.width))x\(Int(cell.height)) pt; "
                + "raster \(rep.pixelsWide)x\(rep.pixelsHigh) px; backing scale \(scale)")
        print("draw commands in final frame: \(commandCount)")
        print("")
        print("phase                                            samples   median ns      p95 ns")
        for phase in phases {
            let (median, p95, count) = phase.summary
            print("\(padRight(phase.name, 46))  \(pad(count, 7))  \(pad(median, 10))  \(pad(p95, 10))")
        }
        print("")
        if let peak = scenarioPeakResidentBytes() {
            print("peak resident: \(peak) bytes (\(peak / 1024) KiB)")
        } else {
            print("peak resident: unavailable")
        }
        print("live heap growth: \(heapGrowth) bytes (live bytes, NOT an allocation count)")
        print("frame digest: \(hex(frameDigest)) (FNV-1a over every frame's draw-command count)")
        print("bitmap digest: \(hex(bitmapDigest)) (FNV-1a over the final rasterized frame)")
        print("")
        for phase in phases {
            let (median, p95, count) = phase.summary
            print("BENCH\t\(phase.name)\t\(count)\t\(median)\t\(p95)")
        }
        print("DIGEST\tframe\t\(hex(frameDigest))")
        print("DIGEST\tbitmap\t\(hex(bitmapDigest))")
    }

    private func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return "0x" + String(repeating: "0", count: max(0, 16 - digits.count)) + digits
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

#endif
