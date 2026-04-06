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
    private var constraintComputePipeline: MTLComputePipelineState!
    private var applyConstraintComputePipeline: MTLComputePipelineState!
    private var renderComputePipeline: MTLComputePipelineState!
    private var densitiesComputePipeline: MTLComputePipelineState!
    private var renderPipeline: MTLRenderPipelineState!

    private var particleBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    private var spatialLookup: MTLBuffer!
    private var startIndices: MTLBuffer!
    private var positionDeltaBuffer: MTLBuffer!
    private var renderTexture: MTLTexture!

    private var viewportSize = SIMD2<Float>(0, 0)
    private var lastTime: CFTimeInterval = CACurrentMediaTime()

    private var cachedParticleCount: Int = 1
    private var needsParticleLayout = true
    private var cachedSpawnArea = SIMD2<Float>(repeating: 0)
    private var cachedSpacing: Float = 0
    private var cachedParticleSize: Float = 0
    private var cachedGenerateRandomly: Bool = false
    private var cachedSmoothingRadius: Float = 0
    private var cachedDensityMultiplier: Float = 0
    private var needsDensityCalibration = true

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

        spatialLookup = device.makeBuffer(length: MemoryLayout<LookoutKey>.stride * cachedParticleCount, options: .storageModeShared)
        
        startIndices = device.makeBuffer(length: MemoryLayout<Int32>.stride * cachedParticleCount, options: .storageModeShared)
        positionDeltaBuffer = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * cachedParticleCount, options: .storageModeShared)

        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        for i in 0 ..< cachedParticleCount {
            particles[i] = Particle(position: .zero, predictedPosition: .zero, velocity: .zero, density: .zero, pressure: .zero, padding: .zero, color: .zero)
        }

        cachedSpawnArea = properties.spawnArea
        cachedSpacing = properties.spacing
        cachedParticleSize = properties.particleSize
        cachedGenerateRandomly = properties.generateRandomly
        cachedSmoothingRadius = properties.smoothingRadius
        cachedDensityMultiplier = properties.densityMultiplier
        needsParticleLayout = true
        needsDensityCalibration = true
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
            let constraintFunction = library.makeFunction(name: "solveDensityConstraints")!
            constraintComputePipeline = try device.makeComputePipelineState(function: constraintFunction)
            let applyConstraintFunction = library.makeFunction(name: "applyDensityConstraints")!
            applyConstraintComputePipeline = try device.makeComputePipelineState(function: applyConstraintFunction)
            let renderComputeFunction = library.makeFunction(name: "renderParticlesToTexture")!
            renderComputePipeline = try device.makeComputePipelineState(function: renderComputeFunction)
            let densityComputeFunction = library.makeFunction(name: "calculateDensities")!
            densitiesComputePipeline = try device.makeComputePipelineState(function: densityComputeFunction)

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
        let expectedParticleCount = properties.generateRandomly ? properties.particleCount : layoutMetrics.count
        let densityConfigChanged = properties.smoothingRadius != cachedSmoothingRadius ||
            properties.densityMultiplier != cachedDensityMultiplier
        let spawnConfigChanged = properties.spawnArea != cachedSpawnArea ||
            properties.spacing != cachedSpacing ||
            properties.particleSize != cachedParticleSize || properties.generateRandomly != cachedGenerateRandomly

        if expectedParticleCount != cachedParticleCount {
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

        if densityConfigChanged {
            cachedSmoothingRadius = properties.smoothingRadius
            cachedDensityMultiplier = properties.densityMultiplier
            needsDensityCalibration = true
        }
    }

    func logParticlePositions() {
        guard let particleBuffer, cachedParticleCount > 0 else {
            print("No particle data available")
            return
        }

        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        for i in 0 ..< cachedParticleCount {
            let position = particles[i].position
            print("Particle \(i): (\(position.x), \(position.y))")
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let now = CACurrentMediaTime()
        var dt = Float(now - lastTime)
        dt = 1 / 120
        lastTime = now

        viewportSize = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))

        if needsParticleLayout {
            layoutParticles()
        }

        if needsDensityCalibration {
            calibrateTargetDensity()
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
            particleColor: SIMD3<Float>(Float(properties.particleColor.usingColorSpace(.sRGB)!.redComponent), Float(properties.particleColor.usingColorSpace(.sRGB)!.greenComponent), Float(properties.particleColor.usingColorSpace(.sRGB)!.blueComponent)),
            boundingBox: SIMD2<Float>(Float(properties.boundingBox.x), Float(properties.boundingBox.y)),
            isPaused: (!properties.started || properties.isPaused) ? 1 : 0,
            collisionDamping: properties.collisionDamping,
            activateCollisions: properties.enableCollisions ? 1 : 0,
            smoothingRadius: properties.smoothingRadius,
            pressureMultiplier: properties.pressureMultiplier,
            targetDensity: properties.targetDensity,
            densityMultiplier: properties.densityMultiplier,
            constraintRelaxation: properties.constraintRelaxation,
            artificialPressureStrength: properties.artificialPressureStrength
        )

        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<FrameUniforms>.stride)

        if properties.started && !properties.isPaused {
            preparePredictedParticles(deltaTime: dt)

            for _ in 0 ..< max(properties.pressureIterations, 1) {
                updateCells()

                guard let solverCommandBuffer = commandQueue.makeCommandBuffer() else { return }

                if let densityEncoder = solverCommandBuffer.makeComputeCommandEncoder() {
                    densityEncoder.setComputePipelineState(densitiesComputePipeline)
                    densityEncoder.setBuffer(particleBuffer, offset: 0, index: Int(BufferIndexParticles.rawValue))
                    densityEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                    densityEncoder.setBuffer(spatialLookup, offset: 0, index: Int(BufferIndexLookup.rawValue))
                    densityEncoder.setBuffer(startIndices, offset: 0, index: Int(BufferIndexStartIndices.rawValue))

                    let threadsPerGroup = MTLSize(width: 64, height: 1, depth: 1)
                    let threadsPerGrid = MTLSize(width: cachedParticleCount, height: 1, depth: 1)

                    densityEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    densityEncoder.endEncoding()
                }

                if let constraintEncoder = solverCommandBuffer.makeComputeCommandEncoder() {
                    constraintEncoder.setComputePipelineState(constraintComputePipeline)
                    constraintEncoder.setBuffer(particleBuffer, offset: 0, index: Int(BufferIndexParticles.rawValue))
                    constraintEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                    constraintEncoder.setBuffer(spatialLookup, offset: 0, index: Int(BufferIndexLookup.rawValue))
                    constraintEncoder.setBuffer(startIndices, offset: 0, index: Int(BufferIndexStartIndices.rawValue))
                    constraintEncoder.setBuffer(positionDeltaBuffer, offset: 0, index: Int(BufferIndexPositionDeltas.rawValue))

                    let threadsPerGroup = MTLSize(width: 64, height: 1, depth: 1)
                    let threadsPerGrid = MTLSize(width: cachedParticleCount, height: 1, depth: 1)

                    constraintEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    constraintEncoder.endEncoding()
                }

                if let applyConstraintEncoder = solverCommandBuffer.makeComputeCommandEncoder() {
                    applyConstraintEncoder.setComputePipelineState(applyConstraintComputePipeline)
                    applyConstraintEncoder.setBuffer(particleBuffer, offset: 0, index: Int(BufferIndexParticles.rawValue))
                    applyConstraintEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                    applyConstraintEncoder.setBuffer(positionDeltaBuffer, offset: 0, index: Int(BufferIndexPositionDeltas.rawValue))

                    let threadsPerGroup = MTLSize(width: 64, height: 1, depth: 1)
                    let threadsPerGrid = MTLSize(width: cachedParticleCount, height: 1, depth: 1)

                    applyConstraintEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    applyConstraintEncoder.endEncoding()
                }

                solverCommandBuffer.commit()
                solverCommandBuffer.waitUntilCompleted()
            }
        }

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
            let spawnHalfX = properties.boundingBox.x * 0.5
            let spawnHalfY = properties.boundingBox.y * 0.5
            let radius = properties.particleSize * 0.5

            for i in 0 ..< cachedParticleCount {
                let x = Float.random(in: (-spawnHalfX + radius)...(spawnHalfX - radius))
                let y = Float.random(in: (-spawnHalfY + radius)...(spawnHalfY - radius))

                particles[i] = Particle(
                    position: SIMD2<Float>(x, y),
                    predictedPosition: SIMD2<Float>(x, y),
                    velocity: .zero,
                    density: .zero,
                    pressure: .zero,
                    padding: .zero,
                    color: SIMD3<Float>(0, 1, 1)
                )
            }
            needsParticleLayout = false
        } else {
            let layout = particleLayoutMetrics()
            let diameter = layout.radius * 2
            let step = layout.step

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
                    predictedPosition: SIMD2<Float>(
                        origin.x + Float(i % layout.columns) * step,
                        origin.y + Float(i / layout.columns) * step
                    ),
                    velocity: .zero,
                    density: .zero,
                    pressure: .zero,
                    padding: .zero,
                    color: SIMD3<Float>(0, 1, 1)
                )
            }

            needsParticleLayout = false
        }

        calibrateTargetDensity()
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
    
    func hashCell(x: Int, y: Int) -> Int {
        return (x * 15823) + (y * 973733)
    }
    
    func keyFromHash(_ hash: Int) -> Int {
        let key = hash % cachedParticleCount
        return key >= 0 ? key : key + cachedParticleCount
    }

    func updateCells() {
        let cellSize = max(properties.smoothingRadius, 0.0001)

        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        let spatialLookupMapped = spatialLookup.contents().bindMemory(
            to: LookoutKey.self,
            capacity: cachedParticleCount
        )

        let startIndicesMapped = startIndices.contents().bindMemory(
            to: Int32.self,
            capacity: cachedParticleCount
        )

        var lookupArray = [LookoutKey]()
        lookupArray.reserveCapacity(cachedParticleCount)

        for i in 0..<cachedParticleCount {
            let cellX = Int(floor(particles[i].predictedPosition.x / cellSize))
            let cellY = Int(floor(particles[i].predictedPosition.y / cellSize))

            let hash = hashCell(x: cellX, y: cellY)
            let key = keyFromHash(hash)
            lookupArray.append(
                LookoutKey(index: Int32(i), cellKey: Int32(key))
            )

            startIndicesMapped[i] = -1
        }

        lookupArray.sort { a, b in
            if a.cellKey == b.cellKey {
                return a.index < b.index
            }
            return a.cellKey < b.cellKey
        }

        for i in 0..<cachedParticleCount {
            spatialLookupMapped[i] = lookupArray[i]
        }
        
        for i in 0..<cachedParticleCount {
            let key = spatialLookupMapped[i].cellKey
            let keyPrev = i == 0 ? -1 : spatialLookupMapped[i - 1].cellKey
            if (key != keyPrev) {
                startIndicesMapped[Int(key)] = Int32(i)
            }
        }
    }

    func calibrateTargetDensity() {
        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        var totalDensity: Float = 0
        let sampleCount = min(10, cachedParticleCount)
        guard sampleCount > 0 else { return }

        for i in 0 ..< sampleCount {
            var density: Float = 0
            let point = particles[i].position
            for j in 0 ..< cachedParticleCount {
                let dst = simd_length(particles[j].position - point)
                let r = max(properties.smoothingRadius, 0.0001)
                if dst < r {
                    let volume = Float.pi * pow(r, 4) / 6
                    density += pow(r - dst, 2) / volume
                }
            }
            totalDensity += density
        }

        properties.targetDensity = totalDensity / Float(sampleCount) * properties.densityMultiplier
        needsDensityCalibration = false
    }

    func preparePredictedParticles(deltaTime: Float) {
        let particles = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: cachedParticleCount
        )

        let gravity = SIMD2<Float>(0, -properties.gravity)

        for i in 0 ..< cachedParticleCount {
            particles[i].velocity += gravity * deltaTime
            particles[i].predictedPosition = particles[i].position + particles[i].velocity * deltaTime
            particles[i].density = 0
            particles[i].pressure = 0
        }
    }
}

struct Viewport: NSViewRepresentable {
    @Environment(Properties.self) var properties
    let renderer: Renderer

    func makeCoordinator() -> Renderer {
        renderer
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
