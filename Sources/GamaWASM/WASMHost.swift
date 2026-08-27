//  WASMHost.swift — GamaWASM
//  Browser backend, reactor-style: no blocking main loop. JS drives the
//  module through @_cdecl exports; the module calls back into JS through
//  @_extern(wasm) imports (module "gama"). Frames render as an HTML grid
//  of styled spans built from the same CellBuffer every backend paints.
//
//  Build with the pinned 6.5-dev WASM SDK ([sdk.wasm] in Toolchains.toml):
//    scripts/check-wasm.sh  (product gama-web-demo; Extern is already
//    enabled on this target). Serve WebHost/ next to the .wasm artifact.

import GamaCore
import GamaDraw

#if arch(wasm32)

// MARK: - JS imports (provided by WebHost/gama.js at instantiation)

@_extern(wasm, module: "gama", name: "setHTML")
@_extern(c)
func gama_js_setHTML(_ ptr: UnsafePointer<UInt8>?, _ len: Int32)

@_extern(wasm, module: "gama", name: "setTitle")
@_extern(c)
func gama_js_setTitle(_ ptr: UnsafePointer<UInt8>?, _ len: Int32)

@_extern(wasm, module: "gama", name: "requestFrame")
@_extern(c)
func gama_js_requestFrame()

// MARK: - Host

/// Type-erased shim so the exported C entry points can drive any App.
/// Class-constrained to match the other two erasure sites (EmbedHostBox,
/// GamaHostView.Session): one reference owner for the FrameHost/CellBuffer
/// pair, no existential-box copies on every event.
private protocol AnyWASMHost: AnyObject {
    func frame()
    func handle(_ event: InputEvent)
}

private final class WASMHostBox<A: App>: AnyWASMHost {
    var host: FrameHost
    var buffer: CellBuffer
    var size: Size

    init(app: A, size: Size) throws(SceneConfigurationError) {
        self.host = try FrameHost(app: app)
        self.size = size
        self.buffer = CellBuffer(size: size)
    }

    func handle(_ event: InputEvent) {
        if case .resize(let s) = event {
            size = s
            buffer.resize(s)
        }
        host.handle(event)
        if host.needsFrame { gama_js_requestFrame() }
    }

    func frame() {
        guard host.needsFrame else { return }
        let laid = host.pump(size: size)
        buffer.clearBack()
        CellPainter.paint(laid, into: &buffer)
        let html = HTMLSerializer.grid(from: buffer)
        let bytes = Array(html.utf8)
        bytes.withUnsafeBufferPointer { buf in
            gama_js_setHTML(buf.baseAddress, Int32(buf.count))
        }
        // Focus reconciliation may need one follow-up frame.
        if host.needsFrame { gama_js_requestFrame() }
    }
}

/// Browser-reactor entry point: install an app once from wasm `main`;
/// the `gama_web_v1_*` exports then drive it from JavaScript.
public enum GamaWeb {
    /// The single installed host. wasm32 is single-threaded, which is the
    /// entire justification for `nonisolated(unsafe)` here; a threaded wasm
    /// future must replace this with real isolation.
    private nonisolated(unsafe) static var installed: (any AnyWASMHost)?

    /// Install the app. Call from the module's `main` (wasi reactor runs
    /// top-level code once at `_initialize`). A second call replaces the
    /// previous host wholesale (its subscriptions and state are dropped).
    public static func install<A: App>(
        app: A,
        columns: Int = 100,
        rows: Int = 30
    ) throws(SceneConfigurationError) {
        installed = try WASMHostBox(app: app, size: Size(width: columns, height: rows))
        let title = Array("Gama".utf8)
        title.withUnsafeBufferPointer { gama_js_setTitle($0.baseAddress, Int32($0.count)) }
        gama_js_requestFrame()
    }

    fileprivate static var current: (any AnyWASMHost)? { installed }
}

// MARK: - Exports (called from WebHost/gama.js)
// Explicitly `nonisolated`: these must never acquire actor isolation from a
// future defaultIsolation/NonisolatedNonsendingByDefault adoption — JS calls
// them on whatever thread the wasm host runs. Result `0` means accepted;
// negative values fail closed when installation/configuration did not produce
// a host (`-1`) or when an input code is invalid (`-2`). JavaScript may ignore
// successful results, but no configuration failure traps across the ABI.

@_cdecl("gama_web_v1_frame")
nonisolated func gama_web_v1_frame() -> Int32 {
    guard let host = GamaWeb.current else { return -1 }
    host.frame()
    return 0
}

@_cdecl("gama_web_v1_key")
nonisolated func gama_web_v1_key(
    _ code: Int32,
    _ char: Int32,
    _ shift: Int32,
    _ ctrl: Int32
) -> Int32 {
    // code: JS KeyboardEvent mapping done host-side (see gama.js):
    //   1=up 2=down 3=left 4=right 5=enter 6=escape 7=tab 8=backspace
    //   9=delete 10=home 11=end 12=pageUp 13=pageDown 100+n=Fn
    //   0 => printable, take `char` scalar.
    let key: Key?
    switch code {
    case 1: key = .up
    case 2: key = .down
    case 3: key = .left
    case 4: key = .right
    case 5: key = .enter
    case 6: key = .escape
    case 7: key = shift != 0 ? .backTab : .tab
    case 8: key = .backspace
    case 9: key = .delete
    case 10: key = .home
    case 11: key = .end
    case 12: key = .pageUp
    case 13: key = .pageDown
    case 100...112: key = .function(Int(code) - 99)
    case 0:
        if let scalar = Unicode.Scalar(UInt32(bitPattern: char)) {
            let ch = Character(scalar)
            key = ctrl != 0 && ch.isLetter ? .ctrl(Character(ch.lowercased())) : .character(ch)
        } else {
            key = nil
        }
    default:
        key = nil
    }
    guard let key else { return -2 }
    guard let host = GamaWeb.current else { return -1 }
    host.handle(.key(key))
    return 0
}

@_cdecl("gama_web_v1_pointer")
nonisolated func gama_web_v1_pointer(
    _ col: Int32,
    _ row: Int32,
    _ pressed: Int32
) -> Int32 {
    guard let host = GamaWeb.current else { return -1 }
    host.handle(.pointer(Point(x: Int(col), y: Int(row)), pressed: pressed != 0))
    return 0
}

@_cdecl("gama_web_v1_resize")
nonisolated func gama_web_v1_resize(_ cols: Int32, _ rows: Int32) -> Int32 {
    guard let host = GamaWeb.current else { return -1 }
    host.handle(.resize(Size(width: max(1, Int(cols)), height: max(1, Int(rows)))))
    return 0
}

#endif  // arch(wasm32)

// MARK: - HTML serialization
// Deliberately outside `#if arch(wasm32)`: pure String code with no wasm
// dependency, so it compiles — and is unit-tested — on every host platform.

enum HTMLSerializer {
    /// One <pre> line per row; runs of identical style collapse into one
    /// <span style="..."> — same run-merging the DrawList uses.
    static func grid(from buffer: CellBuffer) -> String {
        var out = ""
        out.reserveCapacity(buffer.size.width * buffer.size.height * 4)
        var currentRow = -1
        buffer.forEachRun { row, _, _, text, style in
            if row != currentRow {
                if currentRow >= 0 { out += "</pre>" }
                out += "<pre class=\"gama-row\">"
                currentRow = row
            }
            out += "<span style=\"\(css(for: style))\">\(escape(text))</span>"
        }
        if currentRow >= 0 { out += "</pre>" }
        return out
    }

    static func css(for style: TextStyle) -> String {
        var s = ""
        var fg = style.foreground
        var bg = style.background
        if style.attributes.contains(.inverse) { swap(&fg, &bg) }
        if !fg.isDefault { s += "color:rgb(\(fg.r),\(fg.g),\(fg.b));" }
        if !bg.isDefault { s += "background:rgb(\(bg.r),\(bg.g),\(bg.b));" }
        if style.attributes.contains(.bold) { s += "font-weight:bold;" }
        if style.attributes.contains(.dim) { s += "opacity:.6;" }
        if style.attributes.contains(.italic) { s += "font-style:italic;" }
        var deco: [String] = []
        if style.attributes.contains(.underline) { deco.append("underline") }
        if style.attributes.contains(.strikethrough) { deco.append("line-through") }
        if !deco.isEmpty { s += "text-decoration:\(deco.joined(separator: " "));" }
        return s
    }

    /// Escapes element *content* only (`&`, `<`, `>`). Attribute values are
    /// never routed through user text: the style attribute comes exclusively
    /// from `css(for:)`, which interpolates integers and fixed literals.
    /// Any future edit that puts run text into an attribute must add quote
    /// escaping here first.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }
}
