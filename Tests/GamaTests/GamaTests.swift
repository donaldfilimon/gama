import CGamaQt
import CxxStdlib
import Testing

@Test func qtVersionIsNonEmpty() {
    let version = String(gama.qtVersion())
    #expect(!version.isEmpty)
    #expect(version.hasPrefix("6."))
}

@Test func greetMentionsQtAndName() {
    let message = String(gama.greet(std.string("Gama")))
    #expect(message.contains("Qt"))
    #expect(message.contains("Gama"))
}

@Test func greetCopiesOwnedSwiftString() {
    // Swift 6.4: never pass Optional into std.string (unavailable API).
    let name: String = "Swift6"
    let message = String(gama.greet(std.string(name)))
    #expect(message.contains(name))
}

@Test func runWithLoggerCallsBackIntoSwift() {
    final class LogBox: @unchecked Sendable {
        var lines: [String] = []
    }

    let box = LogBox()
    let context = Unmanaged.passUnretained(box).toOpaque()
    let thunk: gama.SwiftLog = { line, ctx in
        let text = String(line)
        guard let ctx else { return }
        Unmanaged<LogBox>.fromOpaque(ctx).takeUnretainedValue().lines.append(text)
    }
    gama.runWithLogger(thunk, context)

    #expect(box.lines.count == 4)
    #expect(box.lines.first == "begin")
    #expect(box.lines.last == "end")
    #expect(box.lines.contains(where: { $0.hasPrefix("qt 6.") }))
    #expect(box.lines.contains(where: { $0.contains("Swift") }))
}
