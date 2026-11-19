import AppKit
import MetalKit
import SnowCore

@MainActor
final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let driftPipeline: MTLRenderPipelineState
    let flakePipeline: MTLRenderPipelineState
    let litterPipeline: MTLRenderPipelineState
    let leafPipeline: MTLRenderPipelineState

    init() throws {
        // Avoid waking a discrete GPU just to draw desktop decoration.
        guard let device = MTLCopyAllDevices().first(where: { $0.isLowPower && !$0.isRemovable })
                ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.device = device
        self.queue = queue
        queue.label = "Snowy shared render queue"
        let library: MTLLibrary
        if let url = Bundle.main.url(forResource: "Snow", withExtension: "metallib") {
            library = try device.makeLibrary(URL: url)
        } else {
            // `swift run` development fallback; packaged apps ship a precompiled library.
            guard let url = Bundle.module.url(forResource: "Snow", withExtension: "metal") else {
                throw RendererError.missingShaders
            }
            library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        }
        func pipeline(vertex: String, fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = vertex
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        driftPipeline = try pipeline(vertex: "driftVertex", fragment: "driftFragment")
        flakePipeline = try pipeline(vertex: "flakeVertex", fragment: "flakeFragment")
        litterPipeline = try pipeline(vertex: "driftVertex", fragment: "litterFragment")
        leafPipeline = try pipeline(vertex: "leafVertex", fragment: "leafFragment")
    }
}

enum RendererError: Error {
    case unavailable, missingShaders, allocationFailed
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    let simulation: SnowSimulation
    let view: MTKView
    let spotlightOverlay: SpotlightOverlay
    var beforeFrame: ((TimeInterval, SIMD2<Float>?) -> Void)?
    var cursorPosition: (() -> SIMD2<Float>)?
    var onFailure: (() -> Void)?
    private let context: MetalContext
    private let menuInset: Float
    private let inFlight = DispatchSemaphore(value: 2)
    private var lastFrame: TimeInterval?
    private var slotIndex = 0
    private var slots: [Slot] = []

    private struct FrameUniforms {
        var viewport: SIMD2<Float>
        var time: Float
        var padding: Float = 0
    }

    private struct Slot {
        let particles: MTLBuffer
        let mesh: MTLBuffer
        /// Fall: airborne leaves, rewritten every frame.
        let leaves: MTLBuffer
        /// Fall: resting leaves, rewritten with the mesh.
        let pile: MTLBuffer
        var meshRevision: UInt64 = .max
    }

    /// What one frame draws from its buffer slot.
    private struct Frame {
        let slot: Slot
        let flakes: Int
        let airborneLeaves: Int
        let pileLeaves: Int
        let elevatedPileLeaves: Int
    }

    init(context: MetalContext, size: CGSize, menuInset: Float, budget: SimulationBudget,
         seed: UInt64) throws {
        self.context = context
        self.menuInset = menuInset
        simulation = SnowSimulation(size: SIMD2(Float(size.width), Float(size.height)), budget: budget, seed: seed)
        view = MTKView(frame: CGRect(origin: .zero, size: size), device: context.device)
        spotlightOverlay = SpotlightOverlay(device: context.device)
        super.init()
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.layer?.isOpaque = false
        if let layer = view.layer as? CAMetalLayer {
            layer.isOpaque = false
            layer.maximumDrawableCount = 2
            layer.presentsWithTransaction = false
        }
        view.delegate = self
        for _ in 0..<2 {
            guard let particles = context.device.makeBuffer(
                length: max(16, budget.flakes * MemoryLayout<ParticleInstance>.stride),
                options: .cpuCacheModeWriteCombined),
                  let mesh = context.device.makeBuffer(
                    length: max(16, budget.maximumSnowVertices * MemoryLayout<SnowVertex>.stride),
                    options: .cpuCacheModeWriteCombined),
                  let leaves = context.device.makeBuffer(
                    length: max(32, budget.maximumAirborneLeaves * MemoryLayout<LeafInstance>.stride),
                    options: .cpuCacheModeWriteCombined),
                  let pile = context.device.makeBuffer(
                    length: max(32, budget.pileLeaves * MemoryLayout<LeafInstance>.stride),
                    options: .cpuCacheModeWriteCombined) else { throw RendererError.allocationFailed }
            slots.append(Slot(particles: particles, mesh: mesh, leaves: leaves, pile: pile))
        }
    }

    func apply(policy: RenderPolicy, scale: CGFloat, paused: Bool) {
        simulation.reducedMotion = policy.reducedMotion
        simulation.particleScale = policy.particleScale
        view.preferredFramesPerSecond = policy.framesPerSecond
        let drawableSize = CGSize(width: max(1, (view.bounds.width * scale).rounded(.down)),
                                  height: max(1, (view.bounds.height * scale).rounded(.down)))
        if view.drawableSize != drawableSize { view.drawableSize = drawableSize }
        if view.isPaused != paused {
            lastFrame = nil
            simulation.resetPointer()
            view.isPaused = paused
        }
        if paused { view.releaseDrawables() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // A busy GPU drops a decorative frame; it never stalls the main thread on our buffers.
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        let now = CACurrentMediaTime()
        let cursor = cursorPosition?()
        beforeFrame?(now, cursor)
        let dt = Float(lastFrame.map { now - $0 } ?? (1 / Double(view.preferredFramesPerSecond)))
        lastFrame = now
        simulation.step(dt: dt, cursor: cursor)

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = context.queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let frame = prepareFrame()
        var uniforms = FrameUniforms(viewport: simulation.size, time: Float(now.truncatingRemainder(dividingBy: 3600)))
        encodeDesktop(encoder, frame: frame, uniforms: &uniforms, drawableSize: view.drawableSize,
                      viewHeight: view.bounds.height)
        encoder.endEncoding()
        command.present(drawable)
        encodeSpotlight(command: command, frame: frame, uniforms: uniforms)
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] completed in
            semaphore.signal()
            if completed.status == .error {
                Task { @MainActor in self?.onFailure?() }
            }
        }
        submitted = true
        slotIndex = (slotIndex + 1) % slots.count
        command.commit()
    }

    /// Copies this frame's instances, and the mesh if it changed, into the current buffer slot.
    private func prepareFrame() -> Frame {
        let slot = slots[slotIndex]
        let count = simulation.flakes.count
        let particles = slot.particles.contents().bindMemory(to: ParticleInstance.self,
                                                            capacity: max(1, count))
        var offset = 0
        for particle in simulation.flakes { particles[offset] = ParticleInstance(particle); offset += 1 }
        if count > 0, slot.particles.storageMode == .managed {
            slot.particles.didModifyRange(0..<(count * MemoryLayout<ParticleInstance>.stride))
        }
        let fall = simulation.season == .fall
        let leafStride = MemoryLayout<LeafInstance>.stride
        var airborne = 0
        if fall {
            let capacity = slot.leaves.length / leafStride
            airborne = simulation.writeLeafInstances(
                to: slot.leaves.contents().bindMemory(to: LeafInstance.self, capacity: capacity), capacity: capacity)
            if airborne > 0, slot.leaves.storageMode == .managed {
                slot.leaves.didModifyRange(0..<(airborne * leafStride))
            }
        }
        let pile = fall ? min(simulation.pileLeaves.count, slot.pile.length / leafStride) : 0
        if slot.meshRevision != simulation.meshRevision {
            simulation.mesh.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress, bytes.count > 0 {
                    slot.mesh.contents().copyMemory(from: base, byteCount: bytes.count)
                }
            }
            if !simulation.mesh.isEmpty, slot.mesh.storageMode == .managed {
                slot.mesh.didModifyRange(0..<(simulation.mesh.count * MemoryLayout<SnowVertex>.stride))
            }
            if pile > 0 {
                simulation.pileLeaves.withUnsafeBytes { bytes in
                    if let base = bytes.baseAddress {
                        slot.pile.contents().copyMemory(from: base, byteCount: pile * leafStride)
                    }
                }
                if slot.pile.storageMode == .managed { slot.pile.didModifyRange(0..<(pile * leafStride)) }
            }
            slots[slotIndex].meshRevision = simulation.meshRevision
        }
        return Frame(slot: slot, flakes: count, airborneLeaves: airborne, pileLeaves: pile,
                     elevatedPileLeaves: min(pile, simulation.elevatedPileLeafCount))
    }

    private func encodeDesktop(_ encoder: MTLRenderCommandEncoder, frame: Frame, uniforms: inout FrameUniforms,
                               drawableSize: CGSize, viewHeight: CGFloat) {
        let slot = frame.slot
        let fall = simulation.season == .fall
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        let top = min(Int(drawableSize.height) - 1,
                      max(0, Int(CGFloat(menuInset) * drawableSize.height / max(1, viewHeight))))
        encoder.setScissorRect(MTLScissorRect(x: 0, y: top, width: Int(drawableSize.width),
                                             height: Int(drawableSize.height) - top))
        if !simulation.mesh.isEmpty {
            encoder.setRenderPipelineState(fall ? context.litterPipeline : context.driftPipeline)
            encoder.setVertexBuffer(slot.mesh, offset: 0, index: 0)
            // Elevated Spotlight caps are presented once in their cropped foreground pass.
            // Every other cap and all transported material stay on the desktop plane.
            var start = 0
            for range in simulation.elevatedMeshRanges {
                let lower = max(start, min(simulation.mesh.count, range.lowerBound))
                if lower > start {
                    encoder.drawPrimitives(type: .triangle, vertexStart: start, vertexCount: lower - start)
                }
                start = max(start, min(simulation.mesh.count, range.upperBound))
            }
            if start < simulation.mesh.count {
                encoder.drawPrimitives(type: .triangle, vertexStart: start, vertexCount: simulation.mesh.count - start)
            }
        }
        if frame.flakes > 0 {
            encoder.setRenderPipelineState(context.flakePipeline)
            encoder.setVertexBuffer(slot.particles, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: frame.flakes)
        }
        // Resting leaves over the fill, then everything in the air over them.
        let resting = frame.pileLeaves - frame.elevatedPileLeaves
        if resting > 0 || frame.airborneLeaves > 0 {
            encoder.setRenderPipelineState(context.leafPipeline)
            if resting > 0 {
                encoder.setVertexBuffer(slot.pile, offset: frame.elevatedPileLeaves * MemoryLayout<LeafInstance>.stride,
                                        index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: resting)
            }
            if frame.airborneLeaves > 0 {
                encoder.setVertexBuffer(slot.leaves, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                       instanceCount: frame.airborneLeaves)
            }
        }
    }

    /// Renders the current simulation state offscreen at `scale` pixels per point.
    /// Development only: a change can be looked at without covering the desktop.
    func snapshot(scale: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(simulation.size.x) * scale))
        let height = max(1, Int(CGFloat(simulation.size.y) * scale))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = context.device.hasUnifiedMemory ? .shared : .managed
        let pass = MTLRenderPassDescriptor()
        guard let texture = context.device.makeTexture(descriptor: descriptor),
              let command = context.queue.makeCommandBuffer() else { return nil }
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let frame = prepareFrame()
        var uniforms = FrameUniforms(viewport: simulation.size, time: 0)
        encodeDesktop(encoder, frame: frame, uniforms: &uniforms,
                      drawableSize: CGSize(width: width, height: height), viewHeight: CGFloat(simulation.size.y))
        encoder.endEncoding()
        if descriptor.storageMode == .managed, let blit = command.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        command.commit()
        command.waitUntilCompleted()
        slotIndex = (slotIndex + 1) % slots.count
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                    | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func encodeSpotlight(command: MTLCommandBuffer, frame: Frame, uniforms: FrameUniforms) {
        guard spotlightOverlay.isActive else { return }
        let foreground = spotlightOverlay.view
        let crop = spotlightOverlay.crop
        guard crop.width > 0, crop.height > 0 else { return }
        spotlightOverlay.renderFrame { [self] pass, drawable in
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            // Keep the existing global-coordinate mesh and shader projection. A shifted
            // viewport maps only the cap strip, without a second CPU/GPU mesh.
            let scaleX = foreground.drawableSize.width / crop.width
            let scaleY = foreground.drawableSize.height / crop.height
            encoder.setViewport(MTLViewport(originX: Double(-crop.minX * scaleX),
                                            originY: Double(-crop.minY * scaleY),
                                            width: Double(CGFloat(simulation.size.x) * scaleX),
                                            height: Double(CGFloat(simulation.size.y) * scaleY),
                                            znear: 0, zfar: 1))
            encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(foreground.drawableSize.width),
                                                 height: Int(foreground.drawableSize.height)))
            var constants = uniforms
            let fall = simulation.season == .fall
            encoder.setVertexBytes(&constants, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            encoder.setRenderPipelineState(fall ? context.litterPipeline : context.driftPipeline)
            encoder.setVertexBuffer(frame.slot.mesh, offset: 0, index: 0)
            for range in simulation.elevatedMeshRanges {
                let lower = max(0, min(simulation.mesh.count, range.lowerBound))
                let upper = max(lower, min(simulation.mesh.count, range.upperBound))
                if upper > lower {
                    encoder.drawPrimitives(type: .triangle, vertexStart: lower, vertexCount: upper - lower)
                }
            }
            if frame.elevatedPileLeaves > 0 {
                encoder.setRenderPipelineState(context.leafPipeline)
                encoder.setVertexBuffer(frame.slot.pile, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                       instanceCount: frame.elevatedPileLeaves)
            }
            encoder.endEncoding()
            command.present(drawable)
        }
    }
}
