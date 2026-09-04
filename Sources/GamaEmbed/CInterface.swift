// CInterface.swift — versioned, context-based C embedding ABI.

public import GamaCore
import GamaDraw

private protocol AnyEmbedHost: AnyObject {
    func handle(_ event: InputEvent)
    var needsFrame: Bool { get }
    func frame() -> [UInt8]?
}

private final class EmbedHostBox<A: App>: AnyEmbedHost {
    var pump: HostPump
    var buffer: CellBuffer

    init(app: A, size: Size) throws(SceneConfigurationError) {
        pump = HostPump(host: try FrameHost(app: app), size: size)
        buffer = CellBuffer(size: size)
    }

    var needsFrame: Bool { pump.needsFrame }

    var size: Size { pump.size }

    func handle(_ event: InputEvent) {
        // Eager resize and the buffer resize both live in the shared pump
        // now; this backend keeps only its own encoding.
        pump.handle(event)
    }

    func frame() -> [UInt8]? {
        var encoded: [UInt8]?
        _ = pump.advance(into: &buffer) { painted in
            encoded = DrawList.from(painted).encode()
        }
        return encoded
    }
}

private final class EmbedContext {
    let host: any AnyEmbedHost
    /// Raw storage deliberately: raw memory has no initialization state to
    /// violate, so reusing the buffer frame-over-frame with `copyBytes` is
    /// well-defined (typed `initialize(fromContentsOf:)` on already-
    /// initialized memory is not). Grows to the high-water frame size and
    /// never shrinks; freed with the context.
    var frameStorage: UnsafeMutableRawBufferPointer = .allocate(
        byteCount: 0, alignment: MemoryLayout<UInt8>.alignment)

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

    var scenes: some Scene {
        Window("Gama C Embed", id: "main", role: .primary) {
            VStack {
                Text("Gama C Embed \(count.get())")
                Button("Increment") { count.update { $0 += 1 } }
            }
        }
    }
}

/// Swift-side entry to the versioned C embedding ABI: build a context for
/// any `App` and hand the opaque pointer to a C, JNI, or
/// game-engine host. Status codes and ownership rules live in
/// `GamaEmbed.h`.
public enum GamaEmbed {
    /// Creates an opaque context for a C, JNI, game-engine, or FFI host.
    ///
    /// The returned pointer is owned by the caller and must be released with
    /// `gama_embed_v1_context_destroy`. All calls for a context must occur on
    /// the same render thread. Ownership of the app region transfers into the
    /// retained opaque context.
    public static func makeContext<A: App>(
        app: sending A,
        columns: Int = 80,
        rows: Int = 24
    ) throws(SceneConfigurationError) -> UnsafeMutableRawPointer {
        let size = Size(
            width: min(Int(Int32.max), max(1, columns)),
            height: min(Int(Int32.max), max(1, rows))
        )
        let context = EmbedContext(host: try EmbedHostBox(app: app, size: size))
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

/// Entry points are explicitly `nonisolated`: the C contract is
/// single-render-thread, not main-thread, and these must never inherit
/// actor isolation from a future `defaultIsolation` adoption.
@_cdecl("gama_embed_v1_abi_version")
public nonisolated func gama_embed_v1_abi_version() -> Int32 { 1 }

/// C ABI: creates a context running the built-in diagnostic app.
@_cdecl("gama_embed_v1_context_create")
public nonisolated func gama_embed_v1_context_create(
    _ columns: Int32,
    _ rows: Int32
) -> UnsafeMutableRawPointer? {
    try? GamaEmbed.makeContext(
        app: CEmbedDiagnosticApp(),
        columns: Int(columns),
        rows: Int(rows)
    )
}

/// C ABI: releases a context; the pointer must not be reused afterwards.
@_cdecl("gama_embed_v1_context_destroy")
public nonisolated func gama_embed_v1_context_destroy(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer else { return }
    Unmanaged<EmbedContext>.fromOpaque(pointer).release()
}

/// C ABI: resizes the grid (dimensions clamped to 1...Int32.max).
@_cdecl("gama_embed_v1_resize")
public nonisolated func gama_embed_v1_resize(
    _ pointer: UnsafeMutableRawPointer?,
    _ columns: Int32,
    _ rows: Int32
) -> Int32 {
    guard let context = context(pointer) else { return -1 }
    // Same clamp as create: an untrusted host must not drive the grid
    // beyond Int32 bounds (CellBuffer additionally caps total cell count).
    context.host.handle(
        .resize(
            Size(
                width: min(Int(Int32.max), max(1, Int(columns))),
                height: min(Int(Int32.max), max(1, Int(rows)))
            ))
    )
    return 0
}

/// C ABI: translates and delivers one key event; -2 for unknown codes.
@_cdecl("gama_embed_v1_key")
public nonisolated func gama_embed_v1_key(
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

/// C ABI: delivers one pointer press/release at a grid position.
@_cdecl("gama_embed_v1_pointer")
public nonisolated func gama_embed_v1_pointer(
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

/// C ABI: 1 when state changed since the last frame, 0 when clean.
@_cdecl("gama_embed_v1_needs_frame")
public nonisolated func gama_embed_v1_needs_frame(_ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard let context = context(pointer) else { return -1 }
    return context.host.needsFrame ? 1 : 0
}

/// C ABI: encodes the next frame into context-owned storage. NULL with
/// length 0 means clean; NULL with length -3 means the frame exceeded
/// Int32.max bytes (GAMA_EMBED_ERR_FRAME_TOO_LARGE).
@_cdecl("gama_embed_v1_frame")
public nonisolated func gama_embed_v1_frame(
    _ pointer: UnsafeMutableRawPointer?,
    _ outputLength: UnsafeMutablePointer<Int32>?
) -> UnsafePointer<UInt8>? {
    guard let context = context(pointer) else {
        outputLength?.pointee = -1
        return nil
    }
    guard let bytes = context.host.frame() else {
        outputLength?.pointee = 0  // clean frame — nothing to draw
        return nil
    }
    guard bytes.count <= Int(Int32.max) else {
        outputLength?.pointee = -3  // GAMA_EMBED_ERR_FRAME_TOO_LARGE
        return nil
    }
    if context.frameStorage.count < bytes.count {
        context.frameStorage.deallocate()
        context.frameStorage = .allocate(
            byteCount: bytes.count, alignment: MemoryLayout<UInt8>.alignment)
    }
    context.frameStorage.copyBytes(from: bytes)
    outputLength?.pointee = Int32(bytes.count)
    return context.frameStorage.baseAddress.map {
        UnsafePointer($0.assumingMemoryBound(to: UInt8.self))
    }
}
