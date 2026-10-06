import MetalKit
import UIKit

struct DanmakuGlyphInstance {
    var motion: SIMD4<Float>
    var geometry: SIMD4<Float>
    var uv: SIMD4<Float>
    var color: SIMD4<Float>
}

struct DanmakuStageGlyphInstance {
    var motion: SIMD4<Float>
    var geometry: SIMD4<Float>
    var uv: SIMD4<Float>
    var color: SIMD4<Float>
    var fontTransition: SIMD4<Float>
}

@MainActor
final class MetalDanmakuRenderer {
    private static let fontTransitionClockPeriod: TimeInterval = 64
    let device: MTLDevice
    let atlas: DanmakuGlyphAtlas
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let fragmentFunction: MTLFunction
    private let stageTransitionVertexFunction: MTLFunction?
    private var stageTransitionPipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState
    private var instances: [DanmakuGlyphInstance] = []
    private var stageInstances: [DanmakuStageGlyphInstance] = []
    private var batches: [(page: Int, start: Int, count: Int)] = []
    private var revision = 0
    private var nextSlot = 0
    private var generation = 0
    private let slots = (0..<3).map { _ in Slot() }
    private(set) var activeCount = 0
    private(set) var drawCalls = 0
    private(set) var skippedFrames = 0
    private(set) var submittedFrames = 0

    private final class Slot {
        let available = DispatchSemaphore(value: 1)
        var buffer: MTLBuffer?
        var version = -1
        var stageBuffer: MTLBuffer?
        var stageVersion = -1
    }

    private struct StageUniforms {
        var transform: SIMD4<Float>
        var videoViewport: SIMD4<Float>
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let atlas = DanmakuGlyphAtlas(device: device),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "danmakuGlyphVertex"),
              let fragment = library.makeFunction(name: "danmakuGlyphFragment"),
              let pipeline = Self.makePipeline(device: device, vertex: vertex, fragment: fragment,
                                               label: "Danmaku glyph batch") else { return nil }
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.sAddressMode = .clampToEdge
        sampling.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sampling) else { return nil }
        self.device = device
        self.queue = queue
        self.atlas = atlas
        self.pipeline = pipeline
        self.fragmentFunction = fragment
        self.stageTransitionVertexFunction = library.makeFunction(name: "danmakuGlyphStageVertex")
        self.sampler = sampler
    }

    /// Build the stage-aware pipeline once when this renderer is created.
    func prepareStageTransitionPipeline() -> Bool {
        if stageTransitionPipeline != nil { return true }
        guard let stageTransitionVertexFunction else { return false }
        stageTransitionPipeline = Self.makePipeline(
            device: device,
            vertex: stageTransitionVertexFunction,
            fragment: fragmentFunction,
            label: "Danmaku stage-transition glyph batch"
        )
        return stageTransitionPipeline != nil
    }

    private static func makePipeline(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        label: String
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func layout(for item: DanmakuItem, width: CGFloat, settings: DanmakuSettings,
                scale: CGFloat) -> DanmakuGlyphLayout? {
        let font = DanmakuRenderPolicy.font(for: item, viewportWidth: width,
            scale: settings.danmakuKit.fontScale, weight: settings.danmakuKit.fontWeight)
        return atlas.layout(text: item.text, font: font, scale: scale)
    }

    /// Only called on entry/expiry/rebuild. Motion itself stays entirely in the shader.
    func update(entries: [MetalDanmakuTimeline.Entry], layouts: [String: DanmakuGlyphLayout],
                opacity: Double) {
        var pages = [[DanmakuGlyphInstance]](repeating: [], count: atlas.textures.count)
        var stagePages = [[DanmakuStageGlyphInstance]](repeating: [], count: atlas.textures.count)
        activeCount = 0
        for entry in entries {
            guard let layout = layouts[entry.item.id] else { continue }
            activeCount += 1
            let rgb = entry.item.color
            let color = SIMD4<Float>(Float((rgb >> 16) & 255) / 255,
                Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255, Float(opacity))
            for glyph in layout.glyphs where pages.indices.contains(glyph.pageIndex) {
                let scale = entry.glyphScale
                let motion = SIMD4(Float(entry.startX + glyph.offset.x * scale),
                                   Float(entry.y + glyph.offset.y * scale),
                                   Float(entry.item.time), Float(entry.velocity))
                let geometry = SIMD4(Float(glyph.size.width * scale),
                                     Float(glyph.size.height * scale),
                                     Float(entry.endTime), Float(scale))
                pages[glyph.pageIndex].append(DanmakuGlyphInstance(
                    motion: motion, geometry: geometry, uv: glyph.uvRect, color: color
                ))

                let horizontalAnchor: CGFloat = entry.item.isScrolling ? 0 : 0.5
                let verticalAnchor: CGFloat = entry.item.isBottomAnchored ? 1 : 0
                let stageMotion = SIMD4(
                    Float(entry.startX + glyph.offset.x * scale
                          + (1 - scale) * layout.size.width * horizontalAnchor),
                    Float(entry.y + glyph.offset.y * scale
                          + (1 - scale) * layout.size.height * verticalAnchor),
                    Float(entry.item.time), Float(entry.velocity)
                )
                let stageGeometry = SIMD4(Float(glyph.size.width * scale),
                                          Float(glyph.size.height * scale),
                                          Float(entry.endTime), Float(scale))
                stagePages[glyph.pageIndex].append(DanmakuStageGlyphInstance(
                    motion: stageMotion,
                    geometry: stageGeometry,
                    uv: glyph.uvRect,
                    color: color,
                    fontTransition: SIMD4(
                        Float(glyph.offset.x - layout.size.width * horizontalAnchor),
                        Float(glyph.offset.y - layout.size.height * verticalAnchor),
                        Float((entry.fontScaleSettleStartHostTime ?? 0)
                            .truncatingRemainder(dividingBy: Self.fontTransitionClockPeriod)),
                        Float(entry.fontScaleSettleDuration)
                    )
                ))
            }
        }
        instances.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)
        for (page, glyphs) in pages.enumerated() where !glyphs.isEmpty {
            batches.append((page, instances.count, glyphs.count))
            instances.append(contentsOf: glyphs)
        }
        stageInstances.removeAll(keepingCapacity: true)
        for (page, glyphs) in stagePages.enumerated() where !glyphs.isEmpty {
            stageInstances.append(contentsOf: glyphs)
        }
        revision &+= 1
    }

    #if DEBUG
    var debugDiagnostics: DanmakuRendererDiagnostics?
    private var diagnostics: DanmakuRendererDiagnostics { debugDiagnostics ?? .shared }
    #endif

    func render(view: MTKView, time: TimeInterval, preparationStartedAt: CFTimeInterval? = nil,
                isManualRefresh: Bool = false, stage: MetalDanmakuRenderStage? = nil) {
        #if DEBUG
        let acquisitionStarted = CACurrentMediaTime()
        let start = preparationStartedAt ?? acquisitionStarted
        #endif
        guard view.bounds.width > 0, view.bounds.height > 0,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else {
            #if DEBUG
            diagnostics.recordMetalRenderFailure("drawable-or-pass-unavailable")
            #endif
            return
        }
        #if DEBUG
        let acquisitionFinished = CACurrentMediaTime()
        #endif
        // Never wait on the GPU on the UI thread. A busy slot drops this draw.
        let slot = slots[nextSlot]
        guard slot.available.wait(timeout: .now()) == .success else {
            skippedFrames += 1
            return
        }
        nextSlot = (nextSlot + 1) % slots.count
        var submitted = false
        defer { if !submitted { slot.available.signal() } }
        guard let command = queue.makeCommandBuffer() else {
            #if DEBUG
            diagnostics.recordMetalRenderFailure("command-buffer-unavailable")
            #endif
            return
        }
        let frameInstanceCount = stage == nil ? instances.count : stageInstances.count
        var frameBuffer: MTLBuffer?
        if stage == nil, !instances.isEmpty {
            let bytes = instances.count * MemoryLayout<DanmakuGlyphInstance>.stride
            if slot.buffer == nil || slot.buffer!.length < bytes {
                slot.buffer = device.makeBuffer(length: max(bytes, 64 * 1024), options: .storageModeShared)
                slot.version = -1
            }
            guard let buffer = slot.buffer else {
                #if DEBUG
                diagnostics.recordMetalRenderFailure("instance-buffer-unavailable")
                #endif
                return
            }
            if slot.version != revision {
                instances.withUnsafeBytes { data in
                    if let base = data.baseAddress { buffer.contents().copyMemory(from: base, byteCount: data.count) }
                }
                slot.version = revision
            }
            frameBuffer = buffer
        } else if stage != nil, !stageInstances.isEmpty {
            let bytes = stageInstances.count * MemoryLayout<DanmakuStageGlyphInstance>.stride
            if slot.stageBuffer == nil || slot.stageBuffer!.length < bytes {
                slot.stageBuffer = device.makeBuffer(length: max(bytes, 64 * 1024), options: .storageModeShared)
                slot.stageVersion = -1
            }
            guard let buffer = slot.stageBuffer else {
                #if DEBUG
                diagnostics.recordMetalRenderFailure("stage-instance-buffer-unavailable")
                #endif
                return
            }
            if slot.stageVersion != revision {
                stageInstances.withUnsafeBytes { data in
                    if let base = data.baseAddress { buffer.contents().copyMemory(from: base, byteCount: data.count) }
                }
                slot.stageVersion = revision
            }
            frameBuffer = buffer
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            #if DEBUG
            diagnostics.recordMetalRenderFailure("encoder-unavailable")
            #endif
            return
        }
        drawCalls = 0
        if frameInstanceCount > 0, let buffer = frameBuffer {
            encodeGlyphs(encoder: encoder, buffer: buffer, size: view.bounds.size, time: time,
                         drawableSize: CGSize(width: drawable.texture.width, height: drawable.texture.height),
                         stage: stage)
        }
        encoder.endEncoding()
        command.present(drawable)
        let semaphore = slot.available
        #if DEBUG
        let token = generation
        let diagnostics = diagnostics
        let captureID = diagnostics.captureID
        let shouldRecord = diagnostics.isRecording
        command.addCompletedHandler { [weak self, weak diagnostics] completed in
            semaphore.signal()
            guard shouldRecord else { return }
            let duration = completed.gpuEndTime - completed.gpuStartTime
            let failure = completed.status == .error ? "command-error-\((completed.error as NSError?)?.code ?? -1)" : nil
            Task { @MainActor [weak self, weak diagnostics] in
                guard let self, self.generation == token else { return }
                if let failure {
                    diagnostics?.recordMetalRenderFailure(failure, captureID: captureID)
                    return
                }
                diagnostics?.recordMetalGPU(milliseconds: duration > 0 ? duration * 1_000 : nil, captureID: captureID)
            }
        }
        #else
        command.addCompletedHandler { _ in semaphore.signal() }
        #endif
        submitted = true
        #if DEBUG
        let commitStarted = CACurrentMediaTime()
        #endif
        command.commit()
        #if DEBUG
        let commitFinished = CACurrentMediaTime()
        #endif
        submittedFrames += 1
        #if DEBUG
        diagnostics.recordMetalFrame(
            active: activeCount, glyphs: frameInstanceCount, drawCalls: drawCalls,
            pages: atlas.textures.count, usedPixels: atlas.usedPixels, capacityPixels: atlas.capacityPixels,
            rejected: atlas.rejectedGlyphs, skipped: skippedFrames,
            preparationMs: (CACurrentMediaTime() - start) * 1_000, timestamp: start,
            expectedInterval: view.isPaused ? 0 : 1 / Double(view.preferredFramesPerSecond),
            requestedFPS: view.preferredFramesPerSecond,
            displayMaximumFPS: view.window?.screen.maximumFramesPerSecond ?? 60,
            scenePreparationMs: (acquisitionStarted - start) * 1_000,
            drawableAcquisitionMs: (acquisitionFinished - acquisitionStarted) * 1_000,
            encodingMs: (commitStarted - acquisitionFinished) * 1_000,
            commitMs: (commitFinished - commitStarted) * 1_000, isManualRefresh: isManualRefresh)
        #endif
    }

    private func encodeGlyphs(encoder: MTLRenderCommandEncoder, buffer: MTLBuffer,
                              size: CGSize, time: TimeInterval, drawableSize: CGSize? = nil,
                              stage: MetalDanmakuRenderStage? = nil) {
        encoder.setRenderPipelineState(stage == nil ? pipeline : (stageTransitionPipeline ?? pipeline))
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var frame = SIMD4<Float>(Float(size.width), Float(size.height), Float(time),
                                 stage == nil ? 0 : Float(CACurrentMediaTime()
                                    .truncatingRemainder(dividingBy: Self.fontTransitionClockPeriod)))
        encoder.setVertexBytes(&frame, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        if let stage {
            var uniforms = StageUniforms(
                transform: SIMD4(Float(stage.transform.scale), Float(stage.transform.translation.x),
                                 Float(stage.transform.translation.y), 0),
                videoViewport: SIMD4(Float(stage.videoViewport.minX), Float(stage.videoViewport.minY),
                                     Float(stage.videoViewport.width), Float(stage.videoViewport.height))
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<StageUniforms>.stride, index: 2)
            if let drawableSize {
                let scaleX = drawableSize.width / max(size.width, 1)
                let scaleY = drawableSize.height / max(size.height, 1)
                let minX = max(0, Int(floor(stage.videoViewport.minX * scaleX)))
                let minY = max(0, Int(floor(stage.videoViewport.minY * scaleY)))
                let maxX = min(Int(drawableSize.width), Int(ceil(stage.videoViewport.maxX * scaleX)))
                let maxY = min(Int(drawableSize.height), Int(ceil(stage.videoViewport.maxY * scaleY)))
                if maxX > minX, maxY > minY {
                    encoder.setScissorRect(MTLScissorRect(x: minX, y: minY,
                                                          width: maxX - minX, height: maxY - minY))
                }
            }
        }
        encoder.setFragmentSamplerState(sampler, index: 0)
        for batch in batches {
            encoder.setFragmentTexture(atlas.textures[batch.page], index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                instanceCount: batch.count, baseInstance: batch.start)
            drawCalls += 1
        }
    }

    #if DEBUG
    /// Offscreen shader validation only; not used by the playback draw loop.
    func debugRenderOffscreen(size: CGSize, time: TimeInterval) -> MTLTexture? {
        guard size.width > 0, size.height > 0, size.width <= 2048, size.height <= 2048,
              !instances.isEmpty else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let buffer = instances.withUnsafeBytes { data -> MTLBuffer? in
            guard let base = data.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: data.count, options: .storageModeShared)
        }
        guard let buffer else { encoder.endEncoding(); return nil }
        drawCalls = 0
        encodeGlyphs(encoder: encoder, buffer: buffer, size: size, time: time)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        return command.status == .completed ? texture : nil
    }
    #endif

    func reset() {
        generation &+= 1
        activeCount = 0
        #if DEBUG
        diagnostics.clearMetalActiveCount()
        #endif
        instances.removeAll(keepingCapacity: false)
        stageInstances.removeAll(keepingCapacity: false)
        batches.removeAll(keepingCapacity: false)
        atlas.reset()
        revision &+= 1
        // In-flight command buffers retain their resources; do not mutate their bytes.
        for slot in slots {
            slot.buffer = nil
            slot.version = -1
            slot.stageBuffer = nil
            slot.stageVersion = -1
        }
    }
}
