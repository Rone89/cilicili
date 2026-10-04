import MetalKit
import UIKit

struct DanmakuGlyphInstance {
    var motion: SIMD4<Float>
    var geometry: SIMD4<Float>
    var uv: SIMD4<Float>
    var color: SIMD4<Float>
}

@MainActor
final class MetalDanmakuRenderer {
    let device: MTLDevice
    let atlas: DanmakuGlyphAtlas
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var instances: [DanmakuGlyphInstance] = []
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
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let atlas = DanmakuGlyphAtlas(device: device),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "danmakuGlyphVertex"),
              let fragment = library.makeFunction(name: "danmakuGlyphFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Experimental danmaku glyph batch"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
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
        self.sampler = sampler
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
        activeCount = 0
        for entry in entries {
            guard let layout = layouts[entry.item.id] else { continue }
            activeCount += 1
            let rgb = entry.item.color
            let color = SIMD4<Float>(Float((rgb >> 16) & 255) / 255,
                Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255, Float(opacity))
            for glyph in layout.glyphs where pages.indices.contains(glyph.pageIndex) {
                pages[glyph.pageIndex].append(DanmakuGlyphInstance(
                    motion: SIMD4(Float(entry.startX + glyph.offset.x), Float(entry.y + glyph.offset.y),
                                  Float(entry.item.time), Float(entry.velocity)),
                    geometry: SIMD4(Float(glyph.size.width), Float(glyph.size.height), Float(entry.endTime), 0),
                    uv: glyph.uvRect, color: color))
            }
        }
        instances.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)
        for (page, glyphs) in pages.enumerated() where !glyphs.isEmpty {
            batches.append((page, instances.count, glyphs.count))
            instances.append(contentsOf: glyphs)
        }
        revision &+= 1
    }

    #if DEBUG
    var debugDiagnostics: DanmakuRendererDiagnostics?
    private var diagnostics: DanmakuRendererDiagnostics { debugDiagnostics ?? .shared }
    #endif

    func render(view: MTKView, time: TimeInterval, preparationStartedAt: CFTimeInterval? = nil,
                isManualRefresh: Bool = false) {
        #if DEBUG
        let acquisitionStarted = CACurrentMediaTime()
        let start = preparationStartedAt ?? acquisitionStarted
        #endif
        guard view.bounds.width > 0, view.bounds.height > 0,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
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
        guard let command = queue.makeCommandBuffer() else { return }
        if !instances.isEmpty {
            let bytes = instances.count * MemoryLayout<DanmakuGlyphInstance>.stride
            if slot.buffer == nil || slot.buffer!.length < bytes {
                slot.buffer = device.makeBuffer(length: max(bytes, 64 * 1024), options: .storageModeShared)
                slot.version = -1
            }
            guard let buffer = slot.buffer else { return }
            if slot.version != revision {
                instances.withUnsafeBytes { data in
                    if let base = data.baseAddress { buffer.contents().copyMemory(from: base, byteCount: data.count) }
                }
                slot.version = revision
            }
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        drawCalls = 0
        if !instances.isEmpty, let buffer = slot.buffer {
            encodeGlyphs(encoder: encoder, buffer: buffer, size: view.bounds.size, time: time)
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
            Task { @MainActor [weak self, weak diagnostics] in
                guard let self, self.generation == token else { return }
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
            active: activeCount, glyphs: instances.count, drawCalls: drawCalls,
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
                              size: CGSize, time: TimeInterval) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var frame = SIMD4<Float>(Float(size.width), Float(size.height), Float(time), 0)
        encoder.setVertexBytes(&frame, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
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
        batches.removeAll(keepingCapacity: false)
        atlas.reset()
        revision &+= 1
        // In-flight command buffers retain their resources; do not mutate their bytes.
        for slot in slots { slot.buffer = nil; slot.version = -1 }
    }
}
