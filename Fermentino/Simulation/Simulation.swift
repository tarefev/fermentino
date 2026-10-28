//
//  Simulation.swift
//  Fermentino
//
//  Владеет буферами и compute-пайплайнами, кодирует один кадр симуляции.
//

import Foundation
import Metal
import simd

final class Simulation {
    struct Config {
        var bodyCount: Int = 5000
        var radius: Float = 0.006
        var gravity: Float = 2.0e-5
        var damping: Float = 0.999
        var restitutionDamping: Float = 0.995
        var substeps: Int = 2
        var collisionIterations: Int = 2
        var cellCapacity: Int = 16
        var frameDt: Float = 1.0 / 60.0
        var attractorStrength: Float = 0.02
    }

    let device: MTLDevice
    private(set) var config: Config
    private(set) var params: SimParams

    private var positions: [MTLBuffer]  // ping-pong
    private var currentIndex = 0
    private let previousPositions: MTLBuffer
    private let velocities: MTLBuffer
    private let accelerations: MTLBuffer
    private var cellCounts: MTLBuffer
    private var cellItems: MTLBuffer

    private let clearGridState: MTLComputePipelineState
    private let gravityState: MTLComputePipelineState
    private let integrateState: MTLComputePipelineState
    private let collisionsState: MTLComputePipelineState
    private let finalizeState: MTLComputePipelineState

    var positionBuffer: MTLBuffer { positions[currentIndex] }
    var velocityBuffer: MTLBuffer { velocities }

    init(device: MTLDevice, library: MTLLibrary, config: Config = Config(), aspect: Float) throws {
        self.device = device
        self.config = config

        let count = config.bodyCount
        let float2Size = MemoryLayout<SIMD2<Float>>.stride * count

        positions = [
            device.makeBuffer(length: float2Size, options: .storageModeShared)!,
            device.makeBuffer(length: float2Size, options: .storageModeShared)!,
        ]
        previousPositions = device.makeBuffer(length: float2Size, options: .storageModePrivate)!
        velocities = device.makeBuffer(length: float2Size, options: .storageModeShared)!
        accelerations = device.makeBuffer(length: float2Size, options: .storageModePrivate)!
        positions[0].label = "positionsA"
        positions[1].label = "positionsB"
        velocities.label = "velocities"

        func makeState(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else {
                throw SimulationError.missingFunction(name)
            }
            return try device.makeComputePipelineState(function: fn)
        }
        clearGridState = try makeState("clearGrid")
        gravityState = try makeState("computeGravity")
        integrateState = try makeState("integrate")
        collisionsState = try makeState("resolveCollisions")
        finalizeState = try makeState("finalizeVelocity")

        params = SimParams()
        params.bodyCount = UInt32(count)
        params.dt = config.frameDt / Float(config.substeps)
        params.radius = config.radius
        params.gravity = config.gravity
        params.softening = (4.0 * config.radius) * (4.0 * config.radius)
        params.damping = config.damping
        params.restitutionDamping = config.restitutionDamping
        params.cellSize = config.radius * 2.0
        params.cellCapacity = UInt32(config.cellCapacity)
        params.attractorStrength = 0.0

        // Заглушки, пересоздаются в updateAspect
        cellCounts = device.makeBuffer(length: 16, options: .storageModePrivate)!
        cellItems = device.makeBuffer(length: 16, options: .storageModePrivate)!
        updateAspect(aspect)
        seed()
    }

    // MARK: - Setup

    func updateAspect(_ aspect: Float) {
        params.aspect = aspect
        params.worldHalf = SIMD2<Float>(aspect, 1.0)
        let dims = SIMD2<UInt32>(
            UInt32((2.0 * aspect / params.cellSize).rounded(.up)) + 1,
            UInt32((2.0 / params.cellSize).rounded(.up)) + 1
        )
        guard dims != params.gridDims else { return }
        params.gridDims = dims
        let cells = Int(dims.x * dims.y)
        cellCounts = device.makeBuffer(length: MemoryLayout<UInt32>.stride * cells,
                                       options: .storageModePrivate)!
        cellItems = device.makeBuffer(length: MemoryLayout<UInt32>.stride * cells * config.cellCapacity,
                                      options: .storageModePrivate)!
        cellCounts.label = "cellCounts"
        cellItems.label = "cellItems"
    }

    func seed() {
        let count = config.bodyCount
        let pos = positions[currentIndex].contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        let vel = velocities.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        var rng = SystemRandomNumberGenerator()
        let discRadius: Float = min(params.worldHalf.x, params.worldHalf.y) * 0.85

        for i in 0..<count {
            let angle = Float.random(in: 0..<(2 * .pi), using: &rng)
            let r = discRadius * sqrt(Float.random(in: 0..<1, using: &rng))
            let p = SIMD2<Float>(cos(angle), sin(angle)) * r
            pos[i] = p
            // лёгкое вращение, чтобы блоб не схлопывался сразу
            let tangent = SIMD2<Float>(-p.y, p.x)
            vel[i] = tangent * 0.25
        }
    }

    func setAttractor(_ world: SIMD2<Float>?) {
        guard let world else {
            params.attractorStrength = 0.0
            return
        }
        params.attractor = world
        params.attractorStrength = config.attractorStrength
    }

    // MARK: - Frame

    func encode(into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "simulation"

        var p = params
        let count = config.bodyCount
        let cells = Int(p.gridDims.x * p.gridDims.y)

        for _ in 0..<config.substeps {
            // 1. clear grid
            encoder.setComputePipelineState(clearGridState)
            encoder.setBuffer(cellCounts, offset: 0, index: 0)
            encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 1)
            dispatch(encoder, clearGridState, threads: cells)

            // 2. gravity
            encoder.setComputePipelineState(gravityState)
            encoder.setBuffer(positions[currentIndex], offset: 0, index: 0)
            encoder.setBuffer(accelerations, offset: 0, index: 1)
            encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 2)
            encoder.dispatchThreadgroups(
                MTLSize(width: (count + 255) / 256, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)
            )

            // 3. integrate + grid insert
            encoder.setComputePipelineState(integrateState)
            encoder.setBuffer(positions[currentIndex], offset: 0, index: 0)
            encoder.setBuffer(previousPositions, offset: 0, index: 1)
            encoder.setBuffer(velocities, offset: 0, index: 2)
            encoder.setBuffer(accelerations, offset: 0, index: 3)
            encoder.setBuffer(cellCounts, offset: 0, index: 4)
            encoder.setBuffer(cellItems, offset: 0, index: 5)
            encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 6)
            dispatch(encoder, integrateState, threads: count)

            // 4. collisions, ping-pong
            for _ in 0..<config.collisionIterations {
                let next = 1 - currentIndex
                encoder.setComputePipelineState(collisionsState)
                encoder.setBuffer(positions[currentIndex], offset: 0, index: 0)
                encoder.setBuffer(positions[next], offset: 0, index: 1)
                encoder.setBuffer(cellCounts, offset: 0, index: 2)
                encoder.setBuffer(cellItems, offset: 0, index: 3)
                encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 4)
                dispatch(encoder, collisionsState, threads: count)
                currentIndex = next
            }

            // 5. velocity from displacement
            encoder.setComputePipelineState(finalizeState)
            encoder.setBuffer(positions[currentIndex], offset: 0, index: 0)
            encoder.setBuffer(previousPositions, offset: 0, index: 1)
            encoder.setBuffer(velocities, offset: 0, index: 2)
            encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 3)
            dispatch(encoder, finalizeState, threads: count)
        }

        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder,
                          _ state: MTLComputePipelineState,
                          threads: Int) {
        let width = min(state.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreadgroups(
            MTLSize(width: (threads + width - 1) / width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }
}

enum SimulationError: Error {
    case missingFunction(String)
}
