//
//  Renderer.swift
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

import Metal
import MetalKit
import SwiftUI

final class Renderer: NSObject, MTKViewDelegate {
    var properties: Properties = .init()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var computePipeline: MTLComputePipelineState!
    private var renderComputePipeline: MTLComputePipelineState!
    private var renderPipeline: MTLRenderPipelineState!

    private var particleBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    private var renderTexture: MTLTexture!

    private var viewportSize = SIMD2<Float>(0, 0)
    private var lastTime: CFTimeInterval = CACurrentMediaTime()

    private var cachedParticleCount: Int = 1
    private var needsParticleLayout = true
    private var cachedSpawnArea = SIMD2<Float>(repeating: 0)
    private var cachedSpacing: Float = 0
    private var cachedParticleSize: Float = 0
    private var cachedGenerateRandomly: Bool = false

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else { fatalError("Metal unavailable") }

        self.device = device
        self.commandQueue = commandQueue
        super.init()

        buildPipelines()
        buildBuffers()
    }

    func configure(view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.sampleCount = 4
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    }

    func buildBuffers() {
        if properties.generateRandomly == false {
            cachedParticleCount = particleLayoutMetrics().count
        } else {
            cachedParticleCount = properties.particleCount
        }

        let particleStride = MemoryLayout<Particle>.stride
        particleBuffer = device.makeBuffer(length: particleStride * cachedParticleCount, options: .storageModeShared)

        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<FrameUniforms>.stride,
            options: .storageModeShared
        )

        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        for i in 0 ..< cachedParticleCount {
            particles[i] = Particle(position: .zero, velocity: .zero, color: .zero)
        }

        cachedSpawnArea = properties.spawnArea
        cachedSpacing = properties.spacing
        cachedParticleSize = properties.particleSize
        cachedGenerateRandomly = properties.generateRandomly
        needsParticleLayout = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2(Float(size.width), Float(size.height))
        needsParticleLayout = true
    }

    func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Missing default Metal library")
        }

        do {
            let computeFunction = library.makeFunction(name: "updateParticles")!
            computePipeline = try device.makeComputePipelineState(function: computeFunction)
            let renderComputeFunction = library.makeFunction(name: "renderParticlesToTexture")!
            renderComputePipeline = try device.makeComputePipelineState(function: renderComputeFunction)

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "renderVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "renderFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.rasterSampleCount = 4

            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Pipeline creation failed \(error)")
        }
    }

    func reloadConfig() {
        let layoutMetrics = particleLayoutMetrics()
        let spawnConfigChanged = properties.spawnArea != cachedSpawnArea ||
            properties.spacing != cachedSpacing ||
            properties.particleSize != cachedParticleSize || properties.generateRandomly != cachedGenerateRandomly

        if layoutMetrics.count != cachedParticleCount {
            buildBuffers()
            return
        }

        if spawnConfigChanged {
            cachedSpawnArea = properties.spawnArea
            cachedSpacing = properties.spacing
            cachedParticleSize = properties.particleSize
            cachedGenerateRandomly = properties.generateRandomly
            needsParticleLayout = true
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let now = CACurrentMediaTime()
        let dt = Float(now - lastTime)
        lastTime = now

        viewportSize = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))

        if needsParticleLayout {
            layoutParticles()
        }

        updateRenderTexture(size: drawable.texture.width > 0 && drawable.texture.height > 0
            ? SIMD2<Int>(drawable.texture.width, drawable.texture.height)
            : SIMD2<Int>(Int(viewportSize.x), Int(viewportSize.y)))
        guard renderTexture != nil else { return }

        var uniforms = FrameUniforms(
            viewportSize: viewportSize,
            gravity: properties.gravity,
            pointSize: properties.particleSize,
            particleCount: UInt32(cachedParticleCount),
            deltaTime: dt,
            particleColor: SIMD3<Float>(Float(properties.particleColor.redComponent), Float(properties.particleColor.greenComponent), Float(properties.particleColor.blueComponent)),
            boundingBox: SIMD2<Float>(Float(properties.boundingBox.x), Float(properties.boundingBox.y)),
            isPaused: (!properties.started || properties.isPaused) ? 1 : 0,
            collisionDamping: properties.collisionDamping,
            activateCollisions: properties.enableCollisions ? 1 : 0,
            smoothingRadius: properties.smoothingRadius,
            pressureMultiplier: properties.pressureMultiplier,
            targetDensity: properties.targetDensity
        )

        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<FrameUniforms>.stride)

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(computePipeline)
            computeEncoder.setBuffer(particleBuffer, offset: 0, index: Int(BufferIndexParticles.rawValue))
            computeEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

            let threadsPerGroup = MTLSize(width: 64, height: 1, depth: 1)
            let threadsPerGrid = MTLSize(width: cachedParticleCount, height: 1, depth: 1)

            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
        }

        if let renderComputeEncoder = commandBuffer.makeComputeCommandEncoder() {
            renderComputeEncoder.setComputePipelineState(renderComputePipeline)
            renderComputeEncoder.setBuffer(particleBuffer, offset: 0, index: Int(BufferIndexParticles.rawValue))
            renderComputeEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            renderComputeEncoder.setTexture(renderTexture, index: Int(TextureIndexRenderTarget.rawValue))

            let threadWidth = renderComputePipeline.threadExecutionWidth
            let threadHeight = max(1, renderComputePipeline.maxTotalThreadsPerThreadgroup / threadWidth)
            let threadsPerGroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
            let threadsPerGrid = MTLSize(width: renderTexture.width, height: renderTexture.height, depth: 1)

            renderComputeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            renderComputeEncoder.endEncoding()
        }

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setFragmentTexture(renderTexture, index: Int(TextureIndexRenderTarget.rawValue))
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func layoutParticles() {
        guard cachedParticleCount > 0 else { return }

        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        if properties.generateRandomly {
            cachedParticleCount = properties.particleCount
            let scale = viewportSize.x / 100
            let half = SIMD2<Float>(50.0, viewportSize.y / viewportSize.x * 50.0)
            let radius = properties.particleSize * 0.5

            for i in 0 ..< cachedParticleCount {
                let x = Float.random(in: (-half.x + radius)...(half.x - radius))
                let y = Float.random(in: (-half.y + radius)...(half.y - radius))

                particles[i] = Particle(
                    position: SIMD2<Float>(x, y),
                    velocity: .zero,
                    color: SIMD3<Float>(0, 1, 1)
                )
            }
            needsParticleLayout = false
        } else {
            let layout = particleLayoutMetrics()
            let diameter = layout.radius * 2
            let step = layout.step

            let bounds = properties.boundingBox

            let occupiedSize = SIMD2<Float>(
                diameter + Float(layout.columns - 1) * step,
                diameter + Float(layout.rows - 1) * step
            )

            // WORLD SPACE: center at (0,0)
            let origin = -occupiedSize * 0.5 + SIMD2<Float>(repeating: layout.radius)

            for i in 0 ..< cachedParticleCount {
                particles[i] = Particle(
                    position: SIMD2<Float>(
                        origin.x + Float(i % layout.columns) * step,
                        origin.y + Float(i / layout.columns) * step
                    ),
                    velocity: .zero,
                    color: SIMD3<Float>(0, 1, 1)
                )
            }

            needsParticleLayout = false
        }
    }

    func particleLayoutMetrics() -> (count: Int, columns: Int, rows: Int, radius: Float, step: Float) {
        let radius = max(properties.particleSize * 0.5, 0.5)
        let step = max(radius * 2 + max(properties.spacing, 0), 1)
        let spawnArea = SIMD2<Float>(
            max(properties.spawnArea.x, 0),
            max(properties.spawnArea.y, 0)
        )
        let columns = max(Int(floor(max(spawnArea.x - radius * 2, 0) / step)) + 1, 1)
        let rows = max(Int(floor(max(spawnArea.y - radius * 2, 0) / step)) + 1, 1)
        return (columns * rows, columns, rows, radius, step)
    }

    func updateRenderTexture(size: SIMD2<Int>) {
        guard size.x > 0, size.y > 0 else { return }

        if renderTexture?.width == size.x, renderTexture?.height == size.y {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size.x,
            height: size.y,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        renderTexture = device.makeTexture(descriptor: descriptor)
    }
}

struct Viewport: NSViewRepresentable {
    @Environment(Properties.self) var properties

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.properties = properties
        context.coordinator.reloadConfig()
    }
}
