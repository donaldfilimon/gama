// RenderPipeline.swift — Render pipeline protocol and supporting types
// Part of GamaCore

// MARK: - Vertex Format

/// The data format of a vertex attribute.
public enum VertexFormat: Sendable {
    /// A single 32-bit float scalar.
    case float
    /// A 2-component 32-bit float vector.
    case float2
    /// A 3-component 32-bit float vector.
    case float3
    /// A 4-component 32-bit float vector.
    case float4
    /// A single 32-bit signed integer scalar.
    case int
    /// A 2-component 32-bit signed integer vector.
    case int2
    /// A 3-component 32-bit signed integer vector.
    case int3
    /// A 4-component 32-bit signed integer vector.
    case int4
    /// A 4-component 8-bit unsigned normalized vector.
    case uchar4Normalized
}

// MARK: - Vertex Step Function

/// Controls how vertex buffer data is stepped through during rendering.
public enum VertexStepFunction: Sendable {
    /// Attribute data is advanced per vertex.
    case perVertex
    /// Attribute data is advanced per instance.
    case perInstance
}

// MARK: - Vertex Attribute

/// Describes a single vertex attribute within a vertex buffer layout.
public struct GPUVertexAttribute: Sendable {
    /// The data format of the attribute.
    public var format: VertexFormat

    /// The byte offset of the attribute within the vertex buffer stride.
    public var offset: Int

    /// The shader location (attribute index) this attribute maps to.
    public var shaderLocation: UInt32

    /// Creates a vertex attribute descriptor.
    /// - Parameters:
    ///   - format: The data format of the attribute.
    ///   - offset: The byte offset within the vertex stride.
    ///   - shaderLocation: The shader attribute index.
    public init(format: VertexFormat, offset: Int, shaderLocation: UInt32) {
        self.format = format
        self.offset = offset
        self.shaderLocation = shaderLocation
    }
}

// MARK: - Vertex Buffer Layout

/// Describes the layout of a single vertex buffer bound during rendering.
public struct GPUVertexBufferLayout: Sendable {
    /// The stride in bytes between consecutive vertices.
    public var stride: Int

    /// How the buffer data is stepped (per vertex or per instance).
    public var stepFunction: VertexStepFunction

    /// The attributes contained within each vertex of this buffer.
    public var attributes: [GPUVertexAttribute]

    /// Creates a vertex buffer layout.
    /// - Parameters:
    ///   - stride: The byte stride between consecutive vertices.
    ///   - stepFunction: The step function (per-vertex or per-instance).
    ///   - attributes: The vertex attributes in this buffer.
    public init(stride: Int, stepFunction: VertexStepFunction = .perVertex, attributes: [GPUVertexAttribute]) {
        self.stride = stride
        self.stepFunction = stepFunction
        self.attributes = attributes
    }
}

// MARK: - Blend Factor

/// A factor used in the blending equation.
public enum BlendFactor: Sendable {
    /// Factor is 0.
    case zero
    /// Factor is 1.
    case one
    /// Factor is source alpha.
    case sourceAlpha
    /// Factor is (1 - source alpha).
    case oneMinusSourceAlpha
    /// Factor is destination alpha.
    case destinationAlpha
    /// Factor is (1 - destination alpha).
    case oneMinusDestinationAlpha
}

// MARK: - Blend Operation

/// The arithmetic operation applied during blending.
public enum BlendOperation: Sendable {
    /// Result = source + destination.
    case add
    /// Result = source - destination.
    case subtract
    /// Result = destination - source.
    case reverseSubtract
    /// Result = min(source, destination).
    case min
    /// Result = max(source, destination).
    case max
}

// MARK: - Color Target State

/// Describes the blending and format configuration for a single color attachment.
public struct GPUColorTargetState: Sendable {
    /// The pixel format of the color attachment.
    public var format: PixelFormat

    /// Whether blending is enabled for this target.
    public var blendEnabled: Bool

    /// The blend factor for the source RGB components.
    public var sourceRGBBlendFactor: BlendFactor

    /// The blend factor for the destination RGB components.
    public var destinationRGBBlendFactor: BlendFactor

    /// The blend operation for RGB components.
    public var rgbBlendOperation: BlendOperation

    /// The blend factor for the source alpha component.
    public var sourceAlphaBlendFactor: BlendFactor

    /// The blend factor for the destination alpha component.
    public var destinationAlphaBlendFactor: BlendFactor

    /// The blend operation for the alpha component.
    public var alphaBlendOperation: BlendOperation

    /// A bitmask controlling which color channels are written. Defaults to `.all`.
    public var writeMask: ColorWriteMask

    /// Creates a color target state.
    /// - Parameters:
    ///   - format: The pixel format of the color attachment.
    ///   - blendEnabled: Whether blending is enabled. Defaults to `false`.
    ///   - sourceRGBBlendFactor: Source RGB blend factor. Defaults to `.one`.
    ///   - destinationRGBBlendFactor: Destination RGB blend factor. Defaults to `.zero`.
    ///   - rgbBlendOperation: RGB blend operation. Defaults to `.add`.
    ///   - sourceAlphaBlendFactor: Source alpha blend factor. Defaults to `.one`.
    ///   - destinationAlphaBlendFactor: Destination alpha blend factor. Defaults to `.zero`.
    ///   - alphaBlendOperation: Alpha blend operation. Defaults to `.add`.
    ///   - writeMask: Color channel write mask. Defaults to `.all`.
    public init(
        format: PixelFormat,
        blendEnabled: Bool = false,
        sourceRGBBlendFactor: BlendFactor = .one,
        destinationRGBBlendFactor: BlendFactor = .zero,
        rgbBlendOperation: BlendOperation = .add,
        sourceAlphaBlendFactor: BlendFactor = .one,
        destinationAlphaBlendFactor: BlendFactor = .zero,
        alphaBlendOperation: BlendOperation = .add,
        writeMask: ColorWriteMask = .all
    ) {
        self.format = format
        self.blendEnabled = blendEnabled
        self.sourceRGBBlendFactor = sourceRGBBlendFactor
        self.destinationRGBBlendFactor = destinationRGBBlendFactor
        self.rgbBlendOperation = rgbBlendOperation
        self.sourceAlphaBlendFactor = sourceAlphaBlendFactor
        self.destinationAlphaBlendFactor = destinationAlphaBlendFactor
        self.alphaBlendOperation = alphaBlendOperation
        self.writeMask = writeMask
    }
}

// MARK: - Render Pipeline Descriptor

/// A complete description of a render pipeline's configuration.
///
/// Use this to create a ``GPURenderPipeline`` from a ``GPUDevice``.
public struct GPURenderPipelineDescriptor: Sendable {
    /// The vertex shader function.
    public var vertexFunction: GPUShaderFunction

    /// The optional fragment shader function.
    public var fragmentFunction: GPUShaderFunction?

    /// The vertex buffer layouts describing the vertex input data.
    public var vertexBufferLayouts: [GPUVertexBufferLayout]

    /// The color target states for each color attachment.
    public var colorTargets: [GPUColorTargetState]

    /// The optional depth/stencil attachment format.
    public var depthStencilFormat: PixelFormat?

    /// The depth-stencil state for the pipeline. When set, overrides `depthStencilFormat`.
    public var depthStencilState: GPUDepthStencilState?

    /// The primitive topology to use when interpreting vertex data.
    public var primitiveTopology: PrimitiveTopology

    /// The number of samples per pixel for multisampling. Defaults to `1` (no MSAA).
    public var sampleCount: Int

    /// An optional debug label for the pipeline.
    public var label: String?

    /// Creates a render pipeline descriptor.
    public init(
        vertexFunction: GPUShaderFunction,
        fragmentFunction: GPUShaderFunction? = nil,
        vertexBufferLayouts: [GPUVertexBufferLayout] = [],
        colorTargets: [GPUColorTargetState] = [],
        depthStencilFormat: PixelFormat? = nil,
        depthStencilState: GPUDepthStencilState? = nil,
        primitiveTopology: PrimitiveTopology = .triangle,
        sampleCount: Int = 1,
        label: String? = nil
    ) {
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
        self.vertexBufferLayouts = vertexBufferLayouts
        self.colorTargets = colorTargets
        self.depthStencilFormat = depthStencilFormat
        self.depthStencilState = depthStencilState
        self.primitiveTopology = primitiveTopology
        self.sampleCount = sampleCount
        self.label = label
    }
}

// MARK: - Render Pipeline Protocol

/// A compiled render pipeline state object.
///
/// Created from a ``GPURenderPipelineDescriptor`` via a ``GPUDevice``.
/// Backend modules provide concrete implementations.
public protocol GPURenderPipeline: AnyObject, Sendable {
    /// An optional debug label for the pipeline.
    var label: String? { get }
}
