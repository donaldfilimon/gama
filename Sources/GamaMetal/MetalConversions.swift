// MetalConversions.swift — Helpers to convert GamaCore enums to Metal equivalents
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

// MARK: - PixelFormat → MTLPixelFormat

extension PixelFormat {
    /// Convert a GamaCore `PixelFormat` to its Metal equivalent.
    public var mtlPixelFormat: MTLPixelFormat {
        switch self {
        case .rgba8Unorm:             return .rgba8Unorm
        case .bgra8Unorm:             return .bgra8Unorm
        case .rgba16Float:            return .rgba16Float
        case .rgba32Float:            return .rgba32Float
        case .depth32Float:           return .depth32Float
        case .stencil8:               return .stencil8
        case .depth24UnormStencil8:   return .depth24Unorm_stencil8
        case .depth32FloatStencil8:   return .depth32Float_stencil8
        case .r8Unorm:                return .r8Unorm
        case .r16Float:               return .r16Float
        case .r32Float:               return .r32Float
        case .rg16Float:              return .rg16Float
        }
    }
}

// MARK: - TextureUsage → MTLTextureUsage

extension TextureUsage {
    /// Convert a GamaCore `TextureUsage` to its Metal equivalent.
    public var mtlTextureUsage: MTLTextureUsage {
        var result: MTLTextureUsage = []
        if contains(.shaderRead)         { result.insert(.shaderRead) }
        if contains(.shaderWrite)        { result.insert(.shaderWrite) }
        if contains(.renderTarget)       { result.insert(.renderTarget) }
        // Metal doesn't have explicit transfer source/destination flags;
        // these are implicit for managed/shared storage modes.
        return result
    }
}

// MARK: - TextureDimension → MTLTextureType

extension TextureDimension {
    /// Convert a GamaCore `TextureDimension` to its Metal equivalent.
    public var mtlTextureType: MTLTextureType {
        switch self {
        case .d1: return .type1D
        case .d2: return .type2D
        case .d3: return .type3D
        }
    }
}

// MARK: - BufferUsage → MTLResourceOptions

extension BufferUsage {
    /// Convert a GamaCore `BufferUsage` to Metal resource options.
    ///
    /// Metal doesn't have per-usage-bit resource options the way Vulkan does.
    /// We choose the storage mode based on whether the buffer needs CPU access.
    /// Buffers that are used for transfer or uniform data get shared storage;
    /// pure GPU-side storage buffers use private storage when possible.
    public var mtlResourceOptions: MTLResourceOptions {
        // On Apple Silicon (unified memory), storageModeShared is generally best.
        // For GPU-only buffers we could use storageModePrivate, but shared is
        // simpler and required for CPU-accessible operations like contents().
        return .storageModeShared
    }
}

// MARK: - LoadAction → MTLLoadAction

extension LoadAction {
    /// Convert a GamaCore `LoadAction` to its Metal equivalent.
    public var mtlLoadAction: MTLLoadAction {
        switch self {
        case .load:     return .load
        case .clear:    return .clear
        case .dontCare: return .dontCare
        }
    }
}

// MARK: - StoreAction → MTLStoreAction

extension StoreAction {
    /// Convert a GamaCore `StoreAction` to its Metal equivalent.
    public var mtlStoreAction: MTLStoreAction {
        switch self {
        case .store:    return .store
        case .dontCare: return .dontCare
        }
    }
}

// MARK: - SamplerAddressMode → MTLSamplerAddressMode

extension SamplerAddressMode {
    /// Convert a GamaCore `SamplerAddressMode` to its Metal equivalent.
    public var mtlSamplerAddressMode: MTLSamplerAddressMode {
        switch self {
        case .clampToEdge:  return .clampToEdge
        case .repeat:       return .repeat
        case .mirrorRepeat: return .mirrorRepeat
        case .clampToZero:  return .clampToZero
        }
    }
}

// MARK: - SamplerMinMagFilter → MTLSamplerMinMagFilter

extension SamplerMinMagFilter {
    /// Convert a GamaCore `SamplerMinMagFilter` to its Metal equivalent.
    public var mtlSamplerMinMagFilter: MTLSamplerMinMagFilter {
        switch self {
        case .nearest: return .nearest
        case .linear:  return .linear
        }
    }
}

// MARK: - SamplerMipFilter → MTLSamplerMipFilter

extension SamplerMipFilter {
    /// Convert a GamaCore `SamplerMipFilter` to its Metal equivalent.
    public var mtlSamplerMipFilter: MTLSamplerMipFilter {
        switch self {
        case .notMipmapped: return .notMipmapped
        case .nearest:      return .nearest
        case .linear:       return .linear
        }
    }
}

// MARK: - StencilOperation → MTLStencilOperation

extension StencilOperation {
    /// Convert a GamaCore `StencilOperation` to its Metal equivalent.
    public var mtlStencilOperation: MTLStencilOperation {
        switch self {
        case .keep:           return .keep
        case .zero:           return .zero
        case .replace:        return .replace
        case .incrementClamp: return .incrementClamp
        case .decrementClamp: return .decrementClamp
        case .invert:         return .invert
        case .incrementWrap:  return .incrementWrap
        case .decrementWrap:  return .decrementWrap
        }
    }
}

// MARK: - ColorWriteMask → MTLColorWriteMask

extension ColorWriteMask {
    /// Convert a GamaCore `ColorWriteMask` to its Metal equivalent.
    public var mtlColorWriteMask: MTLColorWriteMask {
        var result: MTLColorWriteMask = []
        if contains(.red)   { result.insert(.red) }
        if contains(.green) { result.insert(.green) }
        if contains(.blue)  { result.insert(.blue) }
        if contains(.alpha) { result.insert(.alpha) }
        return result
    }
}

// MARK: - CompareFunction → MTLCompareFunction

extension CompareFunction {
    /// Convert a GamaCore `CompareFunction` to its Metal equivalent.
    public var mtlCompareFunction: MTLCompareFunction {
        switch self {
        case .never:        return .never
        case .less:         return .less
        case .equal:        return .equal
        case .lessEqual:    return .lessEqual
        case .greater:      return .greater
        case .notEqual:     return .notEqual
        case .greaterEqual: return .greaterEqual
        case .always:       return .always
        }
    }
}

// MARK: - GPUStencilFaceState → MTLStencilDescriptor

extension GPUStencilFaceState {
    /// Convert a GamaCore `GPUStencilFaceState` to a Metal stencil descriptor.
    public var mtlStencilDescriptor: MTLStencilDescriptor {
        let desc = MTLStencilDescriptor()
        desc.stencilCompareFunction = compare.mtlCompareFunction
        desc.stencilFailureOperation = failOperation.mtlStencilOperation
        desc.depthFailureOperation = depthFailOperation.mtlStencilOperation
        desc.depthStencilPassOperation = passOperation.mtlStencilOperation
        desc.readMask = readMask
        desc.writeMask = writeMask
        return desc
    }
}

#endif
