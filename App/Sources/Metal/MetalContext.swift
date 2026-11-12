// MetalContext — owns the Metal device, queue, library and pipeline cache.
// What: one shared entry point for every compute dispatch in the render graph.
// Inputs-outputs: kernel name + textures + params -> encoded compute work.
// Threading: created once on the main actor; encode() is called from the
// render thread only (single command buffer per frame, see RenderGraph).

import Metal
import MetalKit
final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    private var cache: [String: MTLComputePipelineState] = [:]

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        guard let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.library = library
    }

    func pipeline(_ name: String) throws -> MTLComputePipelineState {
        if let cached = cache[name] { return cached }
        guard let function = library.makeFunction(name: name) else {
            throw RenderError.missingFunction(name)
        }
        let state = try device.makeComputePipelineState(function: function)
        cache[name] = state
        return state
    }

    func encode<P>(
        _ name: String,
        _ commandBuffer: MTLCommandBuffer,
        textures: [MTLTexture?],
        params: P,
        grid: MTLSize
    ) throws {
        let state = try pipeline(name)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.noEncoder
        }
        encoder.setComputePipelineState(state)
        for (index, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: index)
        }
        var paramsCopy = params
        encoder.setBytes(&paramsCopy, length: MemoryLayout<P>.stride, index: 0)
        let width = state.threadExecutionWidth
        let height = max(state.maxTotalThreadsPerThreadgroup / width, 1)
        let threadgroup = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()
    }

    /// Buffer-based encode for kernels that take array buffers instead of
    /// a params struct (buildDisplacementField, stampBrushDabs). Buffers
    /// are set at their given indices; no params buffer is set.
    func encode(
        _ name: String,
        _ commandBuffer: MTLCommandBuffer,
        textures: [MTLTexture?],
        buffers: [(index: Int, buffer: MTLBuffer)],
        grid: MTLSize
    ) throws {
        let state = try pipeline(name)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.noEncoder
        }
        encoder.setComputePipelineState(state)
        for (index, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: index)
        }
        for (index, buffer) in buffers {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }
        let width = state.threadExecutionWidth
        let height = max(state.maxTotalThreadsPerThreadgroup / width, 1)
        let threadgroup = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()
    }
}
