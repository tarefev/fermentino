//
//  Renderer.swift
//  Fermentino
//
//  MTKViewDelegate: крутит кадр игры, собирает сцену и рисует её двумя пайплайнами.
//

import Foundation
import MetalKit
import simd

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let game: Game
    var scale: Float = 1

    private let commandQueue: MTLCommandQueue
    private let shapeState: MTLRenderPipelineState
    private let lineState: MTLRenderPipelineState

    private let ringSize = 3
    private var slot = 0
    private let inFlight: DispatchSemaphore
    private var shapeBuffers: [MTLBuffer] = []
    private var lineBuffers: [MTLBuffer] = []
    private let shapeCapacity = 65536
    private let lineCapacity = 16384

    init?(view: MTKView, hud: HUDModel) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.commandQueue = queue
        inFlight = DispatchSemaphore(value: ringSize)

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        let bg = K.COL_BG
        view.clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        func pipeline(_ label: String, _ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = view.colorPixelFormat
            d.colorAttachments[0].isBlendingEnabled = true
            d.colorAttachments[0].rgbBlendOperation = .add
            d.colorAttachments[0].alphaBlendOperation = .add
            d.colorAttachments[0].sourceRGBBlendFactor = .one
            d.colorAttachments[0].sourceAlphaBlendFactor = .one
            d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }

        do {
            shapeState = try pipeline("shapes", "shapeVertex", "shapeFragment")
            lineState = try pipeline("lines", "lineVertex", "lineFragment")
            let sim = try GPUSimulation(device: device, library: library, capacity: 8192)
            game = Game(sim: sim, hud: hud)
        } catch {
            print("Renderer init failed: \(error)")
            return nil
        }
        for i in 0..<ringSize {
            let s = device.makeBuffer(length: MemoryLayout<ShapeInstance>.stride * shapeCapacity, options: .storageModeShared)!
            s.label = "shapes\(i)"
            let l = device.makeBuffer(length: MemoryLayout<LineVertex>.stride * lineCapacity, options: .storageModeShared)!
            l.label = "lines\(i)"
            shapeBuffers.append(s)
            lineBuffers.append(l)
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        game.frame(now: CACurrentMediaTime())

        var builder = SceneBuilder(game: game, size: view.bounds.size, scale: scale)
        let scene = builder.build()
        game.hud.zoneLabel = scene.zoneLabel

        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor else { return }
        inFlight.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { inFlight.signal(); return }
        commandBuffer.label = "render"
        let sema = inFlight
        commandBuffer.addCompletedHandler { _ in sema.signal() }

        let shapeCount = min(scene.shapes.count, shapeCapacity)
        let lineCount = min(scene.lines.count, lineCapacity) / 2 * 2
        let sb = shapeBuffers[slot], lb = lineBuffers[slot]
        slot = (slot + 1) % ringSize
        scene.shapes.withUnsafeBufferPointer { src in
            sb.contents().copyMemory(from: src.baseAddress!, byteCount: MemoryLayout<ShapeInstance>.stride * shapeCount)
        }
        if lineCount > 0 {
            scene.lines.withUnsafeBufferPointer { src in
                lb.contents().copyMemory(from: src.baseAddress!, byteCount: MemoryLayout<LineVertex>.stride * lineCount)
            }
        }

        var uniforms = FrameUniforms()
        uniforms.viewSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { commandBuffer.commit(); return }
        encoder.label = "scene"
        if shapeCount > 0 {
            encoder.setRenderPipelineState(shapeState)
            encoder.setVertexBuffer(sb, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: shapeCount)
        }
        if lineCount > 0 {
            encoder.setRenderPipelineState(lineState)
            encoder.setVertexBuffer(lb, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineCount)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
