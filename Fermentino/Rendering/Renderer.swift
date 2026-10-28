//
//  Renderer.swift
//  Fermentino
//
//  MTKViewDelegate: гоняет симуляцию и рисует тела одним instanced draw.
//

import Foundation
import MetalKit
import simd

final class RendererStats: ObservableObject {
    @Published var fps: Double = 0
    @Published var bodyCount: Int = 0
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let stats: RendererStats
    private let commandQueue: MTLCommandQueue
    private let renderState: MTLRenderPipelineState
    private let simulation: Simulation

    private var frameCounter = 0
    private var lastStatsTime = CACurrentMediaTime()

    init?(view: MTKView, stats: RendererStats) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.commandQueue = queue
        self.stats = stats

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        view.preferredFramesPerSecond = 120
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "bodies"
        descriptor.vertexFunction = library.makeFunction(name: "bodyVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bodyFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            renderState = try device.makeRenderPipelineState(descriptor: descriptor)
            let size = view.drawableSize
            let aspect = size.height > 0 ? Float(size.width / size.height) : 0.5
            simulation = try Simulation(device: device, library: library, aspect: aspect)
        } catch {
            print("Renderer init failed: \(error)")
            return nil
        }
        stats.bodyCount = simulation.config.bodyCount
        super.init()
    }

    // MARK: - Input

    func setAttractor(screenPoint: CGPoint?, in view: MTKView) {
        guard let pt = screenPoint else {
            simulation.setAttractor(nil)
            return
        }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect = simulation.params.aspect
        let x = Float(pt.x / bounds.width * 2 - 1) * aspect
        let y = Float(1 - pt.y / bounds.height * 2)
        simulation.setAttractor(SIMD2<Float>(x, y))
    }

    func reset() {
        simulation.seed()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.height > 0 else { return }
        simulation.updateAspect(Float(size.width / size.height))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "frame"

        simulation.encode(into: commandBuffer)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.label = "render"
        encoder.setRenderPipelineState(renderState)
        encoder.setVertexBuffer(simulation.positionBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(simulation.velocityBuffer, offset: 0, index: 1)
        var p = simulation.params
        encoder.setVertexBytes(&p, length: MemoryLayout<SimParams>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                               instanceCount: simulation.config.bodyCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        updateStats()
    }

    private func updateStats() {
        frameCounter += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastStatsTime
        guard elapsed >= 0.5 else { return }
        let fps = Double(frameCounter) / elapsed
        frameCounter = 0
        lastStatsTime = now
        DispatchQueue.main.async { [stats] in
            stats.fps = fps
        }
    }
}
