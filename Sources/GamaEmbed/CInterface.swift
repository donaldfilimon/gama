// CInterface.swift — versioned, context-based C embedding ABI.

import GamaCore
import GamaDraw

private protocol AnyEmbedHost: AnyObject {
    func handle(_ event: InputEvent)
    var needsFrame: Bool { get }
    func frame() -> [UInt8]?
}

private final class EmbedHostBox<A: App>: AnyEmbedHost {
    var host: FrameHost<A>
    var buffer: CellBuffer
    var size: Size

    init(app: A, size: Size) {
        host = FrameHost(app: app)
        self.size = size
        buffer = CellBuffer(size: size)
    }

    var needsFrame: Bool { host.needsFrame }

    func handle(_ event: InputEvent) {
        if case .resize(let newSize) = event {
            size = newSize
            buffer.resize(newSize)
        }
        host.handle(event)
    }

    func frame() -> [UInt8]? {
        guard host.needsFrame else { return nil }
        let laidOut = host.pump(size: size)
        buffer.clearBack()
        CellPainter.paint(laidOut, into: &buffer)
        return DrawList.from(buffer).encode()
    }
}

private final class EmbedContext {
    let host: any AnyEmbedHost
    var frameStorage: UnsafeMutableBufferPointer<UInt8> = .allocate(capacity: 0)

    init(host: any AnyEmbedHost) {
        self.host = host
    }

    deinit {
        frameStorage.deallocate()
    }
}

/// Small built-in application that lets a pure-C consumer prove the complete
/// ABI lifecycle without requiring an application-specific Swift bootstrap.
private struct CEmbedDiagnosticApp: App {
    let count = Signal(0)

    var content: some View {
        VStack {
            Text("Gama C Embed \(count.get())")
            Button("Increment") { count.update { $0 += 1 } }
        }
    }
}

public enum GamaEmbed {
    /// Creates an opaque context for a C, JNI, game-engine, or FFI host.
    ///
    /// The returned pointer is owned by the caller and must be released with
    /// `gama_embed_v1_context_destroy`. All calls for a context must occur on
    /// the same render thread.
    public static func makeContext<A: App>(
        app: A,
        columns: Int = 80,
        rows: Int = 24
    ) -> UnsafeMutableRawPointer {
        let size = Size(
            width: min(Int(Int32.max), max(1, columns)),
            height: min(Int(Int32.max), max(1, rows))
        )
        let context = EmbedContext(host: EmbedHostBox(app: app, size: size))
        return Unmanaged.passRetained(context).toOpaque()
    }
}

private func context(_ pointer: UnsafeMutableRawPointer?) -> EmbedContext? {
    guard let pointer else { return nil }
    return Unmanaged<EmbedContext>.fromOpaque(pointer).takeUnretainedValue()
}

private func key(code: Int32, scalar: Int32, shift: Int32, control: Int32) -> Key? {
    switch code {
    case 1: return .up
    case 2: return .down
    case 3: return .left
    case 4: return .right
    case 5: return .enter
    case 6: return .escape
    case 7: return shift != 0 ? .backTab : .tab
    case 8: return .backspace
    case 9: return .delete
    case 10: return .home
    case 11: return .end
    case 12: return .pageUp
    case 13: return .pageDown
    case 100...112: return .function(Int(code) - 99)
    case 0:
        guard let unicode = Unicode.Scalar(UInt32(bitPattern: scalar)) else { return nil }
        let character = Character(unicode)
        return control != 0 && character.isLetter
            ? .ctrl(Character(character.lowercased()))
            : .character(character)
    default:
        return nil
    }
}

@_cdecl("gama_embed_v1_context_create")
public func gama_embed_v1_context_create(
    _ columns: Int32,
    _ rows: Int32
) -> UnsafeMutableRawPointer? {
    GamaEmbed.makeContext(
        app: CEmbedDiagnosticApp(),
        columns: Int(columns),
        rows: Int(rows)
    )
}

@_cdecl("gama_embed_v1_context_destroy")
public func gama_embed_v1_context_destroy(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer else { return }
    Unmanaged<EmbedContext>.fromOpaque(pointer).release()
}

@_cdecl("gama_embed_v1_resize")
public func gama_embed_v1_resize(
    _ pointer: UnsafeMutableRawPointer?,
    _ columns: Int32,
    _ rows: Int32
) -> Int32 {
    guard let context = context(pointer) else { return -1 }
    context.host.handle(
        .resize(Size(width: max(1, Int(columns)), height: max(1, Int(rows))))
    )
    return 0
}

@_cdecl("gama_embed_v1_key")
public func gama_embed_v1_key(
    _ pointer: UnsafeMutableRawPointer?,
    _ code: Int32,
    _ scalar: Int32,
    _ shift: Int32,
    _ control: Int32
) -> Int32 {
    guard let context = context(pointer) else { return -1 }
    guard let translated = key(code: code, scalar: scalar, shift: shift, control: control) else {
        return -2
    }
    context.host.handle(.key(translated))
    return 0
}

@_cdecl("gama_embed_v1_pointer")
public func gama_embed_v1_pointer(
    _ pointer: UnsafeMutableRawPointer?,
    _ column: Int32,
    _ row: Int32,
    _ pressed: Int32
) -> Int32 {
    guard let context = context(pointer) else { return -1 }
    context.host.handle(
        .pointer(Point(x: Int(column), y: Int(row)), pressed: pressed != 0)
    )
    return 0
}

@_cdecl("gama_embed_v1_needs_frame")
public func gama_embed_v1_needs_frame(_ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard let context = context(pointer) else { return -1 }
    return context.host.needsFrame ? 1 : 0
}

@_cdecl("gama_embed_v1_frame")
public func gama_embed_v1_frame(
    _ pointer: UnsafeMutableRawPointer?,
    _ outputLength: UnsafeMutablePointer<Int32>?
) -> UnsafePointer<UInt8>? {
    guard let context = context(pointer) else {
        outputLength?.pointee = -1
        return nil
    }
    guard let bytes = context.host.frame(), bytes.count <= Int(Int32.max) else {
        outputLength?.pointee = 0
        return nil
    }
    if context.frameStorage.count < bytes.count {
        context.frameStorage.deallocate()
        context.frameStorage = .allocate(capacity: bytes.count)
    }
    _ = context.frameStorage.initialize(fromContentsOf: bytes)
    outputLength?.pointee = Int32(bytes.count)
    return UnsafePointer(context.frameStorage.baseAddress)
}
