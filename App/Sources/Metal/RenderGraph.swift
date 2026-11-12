// RenderGraph — dirty-flag staged renderer: source -> source-space -> geometry -> output.
// What: caches each stage and re-runs only the stages a change invalidates.
// Intermediates come from a TexturePool (never allocated per frame); the
// displacement field is built from WarpOps + brush dabs every geometry run.
// Inputs-outputs: RetouchState + source texture -> output texture, one command buffer.
// Threading: render() runs on the render thread; markDirty() is called from @MainActor.

import Foundation
import Metal
import MetalKit
import UIKit
import EditorCore
final class RenderGraph {
    private let context: MetalContext
    private let pool: TexturePool
    private var sourceTexture: MTLTexture?
    private var stage2Texture: MTLTexture?
    private var stage3Texture: MTLTexture?
    private var fieldTexture: MTLTexture?

    /// Runtime textures supplied by the view model (analysis masks).
    var skinMaskTexture: MTLTexture?
    var personMaskTexture: MTLTexture?

    /// Analysis results that drive the warp ops (set by the canvas bridge).
    var landmarks: FaceLandmarks?
    var bodyPose: BodyPose?

    private var stage2Dirty = true
    private var stage3Dirty = true
    private(set) var lastStageTimings: [String: Double] = [:]

    /// Interactive resolution while a finger is down (~1.5 MP); full proxy when idle.
    var isInteracting = false
    var interactivePixelBudget = 1_500_000
    var proxyPixelBudget = 4_194_304

    /// Persistent field-build buffers (.shared so the CPU rewrites them).
    private var opsBuffer: MTLBuffer?
    private var dabsBuffer: MTLBuffer?
    private var opCountBuffer: MTLBuffer?
    private var dabCountBuffer: MTLBuffer?
    private var memoryWarningObserver: NSObjectProtocol?

    init(context: MetalContext) {
        self.context = context
        self.pool = TexturePool(device: context.device)
        self.opsBuffer = context.device.makeBuffer(
            length: WarpFieldParams.maxOps * WarpOpParams.expectedStride,
            options: .storageModeShared)
        self.dabsBuffer = context.device.makeBuffer(
            length: WarpFieldParams.maxDabs * BrushDabParams.expectedStride,
            options: .storageModeShared)
        self.opCountBuffer = context.device.makeBuffer(length: 4, options: .storageModeShared)
        self.dabCountBuffer = context.device.makeBuffer(length: 4, options: .storageModeShared)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.pool.purge() }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setSource(_ texture: MTLTexture?) {
        pool.release(stage2Texture)
        pool.release(stage3Texture)
        pool.release(fieldTexture)
        stage2Texture = nil
        stage3Texture = nil
        fieldTexture = nil
        sourceTexture = texture
        pool.purge()
        stage2Dirty = true
        stage3Dirty = true
    }

    /// Skin / source-space change: re-runs stages 2 and 3.
    func markSourceSpaceDirty() {
        stage2Dirty = true
        stage3Dirty = true
    }

    /// Geometry change (slider drag): re-runs only stage 3.
    func markGeometryDirty() {
        stage3Dirty = true
    }

    func markAllDirty() {
        stage2Dirty = true
        stage3Dirty = true
    }

    /// Renders the current state into `output`. Neutral stages are skipped:
    /// if no skin work is active, stage 2 passes the source through.
    func render(state: RetouchState, output: MTLTexture) throws {
        guard let source = sourceTexture else { throw RenderError.textureCreationFailed }
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw RenderError.noCommandBuffer
        }
        let start = CFAbsoluteTimeGetCurrent()
        let grid = MTLSize(width: source.width, height: source.height, depth: 1)
        // Stage 2 — source-space retouch (skin smoothing via low pass + blend).
        if stage2Dirty {
            pool.release(stage2Texture)
            if state.skinIsNeutral {
                stage2Texture = source
            } else {
                guard let low = pool.acquire(
                    width: source.width, height: source.height,
                    pixelFormat: source.pixelFormat,
                    usage: [.shaderRead, .shaderWrite], label: "skinLow") else {
                    throw RenderError.textureCreationFailed
                }
                let smooth = SmoothParams(strength: state.skinSmoothing01,
                                          textureKeep: state.textureKeep01)
                // skinLowPass takes no params buffer; pass SmoothParams anyway
                // so the shared encode() helper keeps one signature. The kernel
                // ignores buffer 0. Its destination is `low` (texture 1).
                try context.encode("skinLowPass", commandBuffer,
                                   textures: [source, low],
                                   params: smooth, grid: grid)
                guard let blended = pool.acquire(
                    width: source.width, height: source.height,
                    pixelFormat: source.pixelFormat,
                    usage: [.shaderRead, .shaderWrite], label: "skinBlended") else {
                    throw RenderError.textureCreationFailed
                }
                let mask: MTLTexture? = skinMaskTexture
                try context.encode("skinSmoothBlend", commandBuffer,
                                   textures: [source, low, mask, blended],
                                   params: smooth, grid: grid)
                // The low pass is consumed by the blend kernel above; it
                // returns to the pool now. Reuse is safe: all work goes
                // through one queue, so the blend read executes before any
                // later kernel that reuses this texture writes it.
                pool.release(low)
                stage2Texture = blended
            }
            stage2Dirty = false
        }
        // Stage 3 — geometry last (face/body warp via displacement field).
        if stage3Dirty {
            pool.release(stage3Texture)
            if state.isGeometryNeutral {
                stage3Texture = stage2Texture ?? source
                pool.retain(stage3Texture)
            } else {
                // Field is nil when sliders are set but no landmarks/pose
                // exist to place the ops (analysis still running, or no
                // face/body found): render unwarped rather than sampling
                // a nil field texture.
                if let field = try rebuildField(
                    state: state, commandBuffer: commandBuffer,
                    width: source.width, height: source.height) {
                    guard let warped = pool.acquire(
                        width: source.width, height: source.height,
                        pixelFormat: source.pixelFormat,
                        usage: [.shaderRead, .shaderWrite], label: "warped") else {
                        throw RenderError.textureCreationFailed
                    }
                    stage3Texture = warped
                    let warp = WarpParams(backgroundLock: state.backgroundLock ? 1 : 0)
                    let stage2 = stage2Texture ?? source
                    try context.encode("applyDisplacement", commandBuffer,
                                       textures: [stage2, field, personMaskTexture, warped],
                                       params: warp, grid: grid)
                } else {
                    stage3Texture = stage2Texture ?? source
                    pool.retain(stage3Texture)
                }
            }
            stage3Dirty = false
        }
        // Stage 4 — output: blit the latest stage into the drawable/export texture.
        if let finalTexture = stage3Texture ?? stage2Texture ?? sourceTexture,
           finalTexture !== output {
            guard let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw RenderError.noEncoder
            }
            blit.copy(from: finalTexture, to: output)
            blit.endEncoding()
        }
        commandBuffer.commit()
        lastStageTimings["totalMs"] = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }

    /// Builds the displacement field texture (half proxy resolution) from
    /// the state's warp ops + brush dabs. Returns nil when there is
    /// nothing to warp (no ops, no dabs). The field texture is pooled and
    /// released on the next rebuild.
    private func rebuildField(
        state: RetouchState,
        commandBuffer: MTLCommandBuffer,
        width: Int,
        height: Int
    ) throws -> MTLTexture? {
        guard WarpFieldParams.stridesMatch() else { throw RenderError.invalidParamsStride }
        var ops: [WarpOp] = []
        if let landmarks, let face = state.faces.first {
            ops.append(contentsOf: faceWarpOps(face: face, landmarks: landmarks))
        }
        if let bodyPose {
            ops.append(contentsOf: bodyWarpOps(body: state.body, pose: bodyPose))
        }
        if let distortion = distortionWarpOp(strength: state.distortionCorrection) {
            ops.append(distortion)
        }
        let dabs = state.brushStrokes.flatMap { brushDabs(from: $0) }
        guard ops.isEmpty == false || dabs.isEmpty == false else { return nil }
        guard let opsBuffer, let dabsBuffer, let opCountBuffer, let dabCountBuffer else {
            throw RenderError.fieldBufferFailed
        }
        let fieldWidth = max(width / 2, 1)
        let fieldHeight = max(height / 2, 1)
        pool.release(fieldTexture)
        guard let field = pool.acquire(
            width: fieldWidth, height: fieldHeight,
            pixelFormat: .rg16Float,
            usage: [.shaderRead, .shaderWrite], label: "displacementField") else {
            throw RenderError.textureCreationFailed
        }
        fieldTexture = field
        let cappedOps = Array(ops.prefix(WarpFieldParams.maxOps))
        write(cappedOps.map { WarpOpParams(from: $0) }, to: opsBuffer)
        writeCount(UInt32(cappedOps.count), to: opCountBuffer)
        let fieldGrid = MTLSize(width: fieldWidth, height: fieldHeight, depth: 1)
        try context.encode(
            "buildDisplacementField", commandBuffer,
            textures: [field],
            buffers: [(index: 1, buffer: opsBuffer), (index: 2, buffer: opCountBuffer)],
            grid: fieldGrid)
        if dabs.isEmpty == false {
            let cappedDabs = Array(dabs.prefix(WarpFieldParams.maxDabs))
            write(cappedDabs.map { BrushDabParams(from: $0) }, to: dabsBuffer)
            writeCount(UInt32(cappedDabs.count), to: dabCountBuffer)
            try context.encode(
                "stampBrushDabs", commandBuffer,
                textures: [field],
                buffers: [(index: 1, buffer: dabsBuffer), (index: 2, buffer: dabCountBuffer)],
                grid: fieldGrid)
        }
        return field
    }

    private func write<T>(_ values: [T], to buffer: MTLBuffer) {
        guard values.isEmpty == false else { return }
        values.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            buffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            // NOTE: no didModifyRange call — the buffers are
            // .storageModeShared, which never needs it, and the call is
            // unavailable on iOS.
        }
    }

    private func writeCount(_ count: UInt32, to buffer: MTLBuffer) {
        var value = count
        withUnsafeBytes(of: &value) { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            buffer.contents().copyMemory(from: baseAddress, byteCount: 4)
            // NOTE: no didModifyRange call — see write(_:to:) above.
        }
    }
}

// NOTE — adaptive resolution: isInteracting selects the interactive pixel
// budget; the canvas downscales its source texture to that budget while a
// finger is down and restores the full proxy when idle (see CanvasView).
