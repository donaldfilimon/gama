// Types.swift — Shared enums and value types for GamaCore
// Part of GamaCore

/// Pixel format for textures and render targets.
public enum PixelFormat: Sendable {
    /// 8-bit unsigned normalized RGBA.
    case rgba8Unorm
    /// 8-bit unsigned normalized BGRA.
    case bgra8Unorm
    /// 16-bit float RGBA.
    case rgba16Float
    /// 32-bit float RGBA.
    case rgba32Float
    /// 32-bit float depth.
    case depth32Float
    /// 8-bit stencil.
    case stencil8
    /// 24-bit unsigned normalized depth with 8-bit stencil.
    case depth24UnormStencil8
    /// 32-bit float depth with 8-bit stencil.
    case depth32FloatStencil8
    /// 8-bit unsigned normalized single channel.
    case r8Unorm
    /// 16-bit float single channel.
    case r16Float
    /// 32-bit float single channel.
    case r32Float
    /// 16-bit float RG.
    case rg16Float
}

/// Usage options for textures.
public struct TextureUsage: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The texture can be read from a shader.
    public static let shaderRead        = TextureUsage(rawValue: 1 << 0)
    /// The texture can be written from a shader.
    public static let shaderWrite       = TextureUsage(rawValue: 1 << 1)
    /// The texture can be used as a render target.
    public static let renderTarget      = TextureUsage(rawValue: 1 << 2)
    /// The texture can be used as a transfer source.
    public static let transferSource    = TextureUsage(rawValue: 1 << 3)
    /// The texture can be used as a transfer destination.
    public static let transferDestination = TextureUsage(rawValue: 1 << 4)
}

/// Usage options for buffers.
public struct BufferUsage: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The buffer can be used as vertex data.
    public static let vertex            = BufferUsage(rawValue: 1 << 0)
    /// The buffer can be used as index data.
    public static let index             = BufferUsage(rawValue: 1 << 1)
    /// The buffer can be used as uniform/constant data.
    public static let uniform           = BufferUsage(rawValue: 1 << 2)
    /// The buffer can be used as shader storage.
    public static let storage           = BufferUsage(rawValue: 1 << 3)
    /// The buffer can be used as a transfer source.
    public static let transferSource    = BufferUsage(rawValue: 1 << 4)
    /// The buffer can be used as a transfer destination.
    public static let transferDestination = BufferUsage(rawValue: 1 << 5)
}

// MARK: - Color Write Mask

/// A bitmask controlling which color channels are written during rendering.
public struct ColorWriteMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let red   = ColorWriteMask(rawValue: 1 << 0)
    public static let green = ColorWriteMask(rawValue: 1 << 1)
    public static let blue  = ColorWriteMask(rawValue: 1 << 2)
    public static let alpha = ColorWriteMask(rawValue: 1 << 3)
    public static let all: ColorWriteMask = [.red, .green, .blue, .alpha]
}

/// Action to perform when loading a render target at the start of a render pass.
public enum LoadAction: Sendable {
    /// Load the existing contents.
    case load
    /// Clear to a specified value.
    case clear
    /// Contents are undefined; the GPU may discard previous data.
    case dontCare
}

/// Action to perform when storing a render target at the end of a render pass.
public enum StoreAction: Sendable {
    /// Store the rendered contents.
    case store
    /// Contents are not needed after the render pass.
    case dontCare
}

/// Primitive topology for draw calls.
public enum PrimitiveTopology: Sendable {
    /// Individual points.
    case point
    /// Individual line segments.
    case line
    /// Connected line strip.
    case lineStrip
    /// Individual triangles.
    case triangle
    /// Connected triangle strip.
    case triangleStrip
}

/// Index buffer element format.
public enum IndexFormat: Sendable {
    /// 16-bit unsigned integer indices.
    case uint16
    /// 32-bit unsigned integer indices.
    case uint32
}

/// Comparison function used for depth/stencil testing.
public enum CompareFunction: Sendable {
    /// Test never passes.
    case never
    /// Test passes if source < destination.
    case less
    /// Test passes if source == destination.
    case equal
    /// Test passes if source <= destination.
    case lessEqual
    /// Test passes if source > destination.
    case greater
    /// Test passes if source != destination.
    case notEqual
    /// Test passes if source >= destination.
    case greaterEqual
    /// Test always passes.
    case always
}

/// RGBA clear color with double-precision components.
public struct ClearColor: Sendable {
    /// Red component (0.0–1.0).
    public var r: Double
    /// Green component (0.0–1.0).
    public var g: Double
    /// Blue component (0.0–1.0).
    public var b: Double
    /// Alpha component (0.0–1.0).
    public var a: Double

    /// Creates a clear color.
    public init(r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// 3D extent (width, height, depth) in texels or pixels.
public struct Extent3D: Sendable {
    /// Width in texels.
    public var width: UInt32
    /// Height in texels.
    public var height: UInt32
    /// Depth in texels (1 for 2D textures).
    public var depth: UInt32

    /// Creates a 3D extent.
    public init(width: UInt32, height: UInt32, depth: UInt32 = 1) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

/// 3D origin offset in texels or pixels.
public struct Origin3D: Sendable {
    /// X offset.
    public var x: UInt32
    /// Y offset.
    public var y: UInt32
    /// Z offset.
    public var z: UInt32

    /// Creates a 3D origin.
    public init(x: UInt32 = 0, y: UInt32 = 0, z: UInt32 = 0) {
        self.x = x
        self.y = y
        self.z = z
    }
}
