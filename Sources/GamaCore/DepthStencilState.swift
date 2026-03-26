// DepthStencilState.swift — Depth and stencil state types for GamaCore
// Part of GamaCore

// MARK: - Stencil Operation

/// An operation performed on a stencil buffer value.
public enum StencilOperation: Sendable {
    case keep
    case zero
    case replace
    case incrementClamp
    case decrementClamp
    case invert
    case incrementWrap
    case decrementWrap
}

// MARK: - Stencil Face State

/// Stencil operation configuration for one face (front or back).
public struct GPUStencilFaceState: Sendable {
    public var compare: CompareFunction
    public var failOperation: StencilOperation
    public var depthFailOperation: StencilOperation
    public var passOperation: StencilOperation
    public var readMask: UInt32
    public var writeMask: UInt32

    public init(
        compare: CompareFunction = .always,
        failOperation: StencilOperation = .keep,
        depthFailOperation: StencilOperation = .keep,
        passOperation: StencilOperation = .keep,
        readMask: UInt32 = 0xFF,
        writeMask: UInt32 = 0xFF
    ) {
        self.compare = compare
        self.failOperation = failOperation
        self.depthFailOperation = depthFailOperation
        self.passOperation = passOperation
        self.readMask = readMask
        self.writeMask = writeMask
    }
}

// MARK: - Depth Stencil Descriptor

/// Full depth and stencil test configuration descriptor for a render pipeline.
///
/// Pass this descriptor to ``GPUDevice/createDepthStencilState(descriptor:)``
/// to obtain a compiled ``GPUDepthStencilStateObject``.
public struct GPUDepthStencilDescriptor: Sendable {
    public var format: PixelFormat
    public var depthWriteEnabled: Bool
    public var depthCompare: CompareFunction
    public var stencilFront: GPUStencilFaceState
    public var stencilBack: GPUStencilFaceState

    public init(
        format: PixelFormat,
        depthWriteEnabled: Bool = true,
        depthCompare: CompareFunction = .less,
        stencilFront: GPUStencilFaceState = GPUStencilFaceState(),
        stencilBack: GPUStencilFaceState = GPUStencilFaceState()
    ) {
        self.format = format
        self.depthWriteEnabled = depthWriteEnabled
        self.depthCompare = depthCompare
        self.stencilFront = stencilFront
        self.stencilBack = stencilBack
    }
}

/// Backward-compatible alias for ``GPUDepthStencilDescriptor``.
public typealias GPUDepthStencilState = GPUDepthStencilDescriptor

// MARK: - Depth Stencil State Object Protocol

/// A compiled depth-stencil state object created from a ``GPUDepthStencilDescriptor``.
///
/// Unlike the descriptor struct, this is a reference-type protocol representing
/// GPU-compiled state that can be bound to a render command encoder via
/// ``GPURenderCommandEncoder/setDepthStencilState(_:)``.
public protocol GPUDepthStencilStateObject: AnyObject, Sendable {
    /// The descriptor used to create this state object.
    var descriptor: GPUDepthStencilDescriptor { get }
}
