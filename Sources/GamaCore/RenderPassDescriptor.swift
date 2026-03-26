// RenderPassDescriptor.swift — Render pass configuration for GamaCore
// Part of GamaCore

// MARK: - Color Attachment

/// Describes a single color attachment for a render pass.
///
/// A color attachment binds a texture as a render target and specifies
/// how the GPU should handle its contents at the start and end of the pass.
public struct GPUColorAttachment: Sendable {
    /// The texture to use as the color render target.
    public var texture: any GPUTexture

    /// The action to perform when loading the attachment at pass start.
    public var loadAction: LoadAction

    /// The action to perform when storing the attachment at pass end.
    public var storeAction: StoreAction

    /// The color to clear the attachment to when ``loadAction`` is `.clear`.
    public var clearColor: ClearColor

    /// Creates a new color attachment.
    /// - Parameters:
    ///   - texture: The texture to render into.
    ///   - loadAction: The load action (default `.clear`).
    ///   - storeAction: The store action (default `.store`).
    ///   - clearColor: The clear color (default opaque black).
    public init(
        texture: any GPUTexture,
        loadAction: LoadAction = .clear,
        storeAction: StoreAction = .store,
        clearColor: ClearColor = ClearColor()
    ) {
        self.texture = texture
        self.loadAction = loadAction
        self.storeAction = storeAction
        self.clearColor = clearColor
    }
}

// MARK: - Depth/Stencil Attachment

/// Describes the depth and stencil attachment for a render pass.
///
/// Combines depth and stencil configuration into a single descriptor since
/// many GPU formats pack both into one texture (e.g., `depth32FloatStencil8`).
public struct GPUDepthStencilAttachment: Sendable {
    /// The texture to use as the depth/stencil render target.
    public var texture: any GPUTexture

    /// The action to perform when loading the depth plane at pass start.
    public var depthLoadAction: LoadAction

    /// The action to perform when storing the depth plane at pass end.
    public var depthStoreAction: StoreAction

    /// The value to clear the depth plane to when ``depthLoadAction`` is `.clear`.
    public var clearDepth: Float

    /// The action to perform when loading the stencil plane at pass start.
    public var stencilLoadAction: LoadAction

    /// The action to perform when storing the stencil plane at pass end.
    public var stencilStoreAction: StoreAction

    /// The value to clear the stencil plane to when ``stencilLoadAction`` is `.clear`.
    public var clearStencil: UInt32

    /// Creates a new depth/stencil attachment.
    /// - Parameters:
    ///   - texture: The depth/stencil texture.
    ///   - depthLoadAction: The depth load action (default `.clear`).
    ///   - depthStoreAction: The depth store action (default `.store`).
    ///   - clearDepth: The depth clear value (default `1.0`).
    ///   - stencilLoadAction: The stencil load action (default `.dontCare`).
    ///   - stencilStoreAction: The stencil store action (default `.dontCare`).
    ///   - clearStencil: The stencil clear value (default `0`).
    public init(
        texture: any GPUTexture,
        depthLoadAction: LoadAction = .clear,
        depthStoreAction: StoreAction = .store,
        clearDepth: Float = 1.0,
        stencilLoadAction: LoadAction = .dontCare,
        stencilStoreAction: StoreAction = .dontCare,
        clearStencil: UInt32 = 0
    ) {
        self.texture = texture
        self.depthLoadAction = depthLoadAction
        self.depthStoreAction = depthStoreAction
        self.clearDepth = clearDepth
        self.stencilLoadAction = stencilLoadAction
        self.stencilStoreAction = stencilStoreAction
        self.clearStencil = clearStencil
    }
}

// MARK: - Render Pass Descriptor

/// Describes the full configuration of a render pass, including all color
/// attachments and an optional depth/stencil attachment.
///
/// Pass an instance of this type to
/// ``GPUCommandBuffer/makeRenderCommandEncoder(descriptor:)`` to begin
/// encoding rendering commands.
public struct GPURenderPassDescriptor: Sendable {
    /// The color attachments for this render pass.
    public var colorAttachments: [GPUColorAttachment]

    /// The optional depth/stencil attachment for this render pass.
    public var depthStencilAttachment: GPUDepthStencilAttachment?

    /// An optional debug label for the render pass.
    public var label: String?

    /// Creates a new render pass descriptor.
    /// - Parameters:
    ///   - colorAttachments: The color attachments to bind.
    ///   - depthStencilAttachment: An optional depth/stencil attachment.
    ///   - label: An optional debug label.
    public init(
        colorAttachments: [GPUColorAttachment],
        depthStencilAttachment: GPUDepthStencilAttachment? = nil,
        label: String? = nil
    ) {
        self.colorAttachments = colorAttachments
        self.depthStencilAttachment = depthStencilAttachment
        self.label = label
    }
}
