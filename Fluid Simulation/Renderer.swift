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
            particles[i] = Particle(position: .zero, color: .zero)
        }

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
        if properties.particleCount != cachedParticleCount {
            cachedParticleCount = properties.particleCount
            buildBuffers()
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
            gravity: 0.0,
            pointSize: properties.particleSize,
            particleCount: UInt32(cachedParticleCount),
            deltaTime: dt,
            particleColor: SIMD3<Float>(Float(properties.particleColor.redComponent), Float(properties.particleColor.greenComponent), Float(properties.particleColor.blueComponent))
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
        guard cachedParticleCount > 0,
              viewportSize.x > 0,
              viewportSize.y > 0
        else { return }

        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        let spacing: Float = 10
        let columns = min(64, cachedParticleCount)
        let rows = Int(ceil(Float(cachedParticleCount) / Float(columns)))
        let gridWidth = Float(columns - 1) * spacing
        let gridHeight = Float(rows - 1) * spacing
        let origin = SIMD2<Float>(
            (viewportSize.x - gridWidth) * 0.5,
            (viewportSize.y - gridHeight) * 0.5
        )

        for i in 0 ..< cachedParticleCount {
            particles[i] = Particle(
                position: SIMD2<Float>(
                    origin.x + Float(i % columns) * spacing,
                    origin.y + Float(i / columns) * spacing
                ),
                color: .zero
            )
        }

        needsParticleLayout = false
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
