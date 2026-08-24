import CGamaQtAdapter
import CxxStdlib
import GamaCore
import GamaDraw

/// Renders the backend-neutral Gama draw list into an owned Qt image surface.
public enum GamaQtRenderer {
    public static func render(_ list: DrawList, into surface: inout gama.QtSurface) {
        surface.clear(0, 0, 0)
        for command in list.commands {
            switch command {
            case .fillRect(let rect, let color):
                surface.fillRect(
                    clamped(rect.minX), clamped(rect.minY),
                    clamped(rect.size.width), clamped(rect.size.height),
                    color.r, color.g, color.b
                )
            case .text(let text, let point, let style):
                let color = style.foreground.isDefault ? Color(r: 255, g: 255, b: 255) : style.foreground
                surface.drawText(
                    std.string(text), clamped(point.x), clamped(point.y),
                    color.r, color.g, color.b
                )
            }
        }
    }

    private static func clamped(_ value: Int) -> Int32 {
        if value > Int(Int32.max) { return .max }
        if value < Int(Int32.min) { return .min }
        return Int32(value)
    }
}

/// Retained Qt-facing frame/event owner. It keeps application state and layout
/// in GamaCore; a QWidget or QPaintDevice adapter only forwards size/input and
/// paints the returned shared draw list.
public final class GamaQtHost<A: App> {
    private var host: FrameHost<A>
    private var buffer: CellBuffer
    public private(set) var drawList: DrawList

    public init(app: A, size: Size) {
        host = FrameHost(app: app)
        buffer = CellBuffer(size: size)
        drawList = DrawList(size: buffer.size)
    }

    public var needsFrame: Bool { host.needsFrame }

    public func resize(_ size: Size) {
        buffer.resize(size)
        host.handle(.resize(buffer.size))
    }

    public func handle(_ event: InputEvent) { host.handle(event) }

    @discardableResult
    public func frame() -> DrawList {
        guard host.needsFrame else { return drawList }
        let laidOut = host.pump(size: buffer.size)
        buffer.clearBack()
        CellPainter.paint(laidOut, into: &buffer)
        drawList = DrawList.from(buffer)
        return drawList
    }

    public func render(into surface: inout gama.QtSurface) {
        GamaQtRenderer.render(frame(), into: &surface)
    }

    public func shutdown() { host.cancelSubscriptions() }
}
