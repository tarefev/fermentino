//
//  GPUSimulation.swift
//  Fermentino
//
//  Буферы тел и связей в общей памяти + запуск подшагов физики на GPU.
//  Один вызов run = SUBSTEPS × (computeForces, integrate), блокирующий: после него CPU
//  читает и правит тела напрямую.
//

import Foundation
import Metal

final class GPUSimulation {
    let device: MTLDevice
    let capacity: Int
    private let queue: MTLCommandQueue
    private let forcesState: MTLComputePipelineState
    private let integrateState: MTLComputePipelineState

    private let bodyBuffer: MTLBuffer
    private let accelBuffer: MTLBuffer
    private let tqBuffer: MTLBuffer
    private let nbrBuffer: MTLBuffer
    private let bondSlotBuffer: MTLBuffer
    private let bondKBuffer: MTLBuffer
    private let bondLenBuffer: MTLBuffer
    private let slotsBuffer: MTLBuffer

    let bodies: UnsafeMutablePointer<Body>
    let bondSlot: UnsafeMutablePointer<Int32>
    let bondK: UnsafeMutablePointer<Float>
    let bondLen: UnsafeMutablePointer<Float>
    let slots: UnsafeMutablePointer<Float>

    init(device: MTLDevice, library: MTLLibrary, capacity: Int) throws {
        self.device = device
        self.capacity = capacity
        guard let q = device.makeCommandQueue() else { throw SimulationError.noQueue }
        queue = q

        func state(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw SimulationError.missingFunction(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        forcesState = try state("computeForces")
        integrateState = try state("integrate")

        func shared(_ length: Int, _ label: String) -> MTLBuffer {
            let b = device.makeBuffer(length: length, options: .storageModeShared)!
            b.label = label
            return b
        }
        let maxCores = Int(FERM_MAX_CORES)
        let maxSlots = Int(FERM_MAX_SLOTS)
        bodyBuffer = shared(MemoryLayout<Body>.stride * capacity, "bodies")
        accelBuffer = shared(MemoryLayout<SIMD2<Float>>.stride * capacity, "accel")
        tqBuffer = shared(MemoryLayout<Float>.stride * capacity, "tq")
        nbrBuffer = shared(MemoryLayout<UInt32>.stride * capacity, "nbr")
        bondSlotBuffer = shared(MemoryLayout<Int32>.stride * maxCores * maxCores, "bondSlot")
        bondKBuffer = shared(MemoryLayout<Float>.stride * maxCores * maxCores, "bondK")
        bondLenBuffer = shared(MemoryLayout<Float>.stride * maxCores * maxCores, "bondLen")
        slotsBuffer = shared(MemoryLayout<Float>.stride * maxCores * maxSlots, "slots")

        bodies = bodyBuffer.contents().bindMemory(to: Body.self, capacity: capacity)
        bondSlot = bondSlotBuffer.contents().bindMemory(to: Int32.self, capacity: maxCores * maxCores)
        bondK = bondKBuffer.contents().bindMemory(to: Float.self, capacity: maxCores * maxCores)
        bondLen = bondLenBuffer.contents().bindMemory(to: Float.self, capacity: maxCores * maxCores)
        slots = slotsBuffer.contents().bindMemory(to: Float.self, capacity: maxCores * maxSlots)
        bodies.initialize(repeating: Body(), count: capacity)
    }

    /// Прогоняет `substeps` подшагов физики и ждёт завершения GPU.
    func run(params: SimParams, substeps: Int) {
        let count = Int(params.bodyCount)
        guard count > 0, let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        commandBuffer.label = "physics"
        var p = params
        let width = min(forcesState.maxTotalThreadsPerThreadgroup, 128)
        let groups = MTLSize(width: (count + width - 1) / width, height: 1, depth: 1)
        let perGroup = MTLSize(width: width, height: 1, depth: 1)

        for _ in 0..<substeps {
            encoder.setComputePipelineState(forcesState)
            encoder.setBuffer(bodyBuffer, offset: 0, index: 0)
            encoder.setBuffer(accelBuffer, offset: 0, index: 1)
            encoder.setBuffer(tqBuffer, offset: 0, index: 2)
            encoder.setBuffer(nbrBuffer, offset: 0, index: 3)
            encoder.setBuffer(bondSlotBuffer, offset: 0, index: 4)
            encoder.setBuffer(bondKBuffer, offset: 0, index: 5)
            encoder.setBuffer(bondLenBuffer, offset: 0, index: 6)
            encoder.setBuffer(slotsBuffer, offset: 0, index: 7)
            encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 8)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: perGroup)

            encoder.setComputePipelineState(integrateState)
            encoder.setBuffer(bodyBuffer, offset: 0, index: 0)
            encoder.setBuffer(accelBuffer, offset: 0, index: 1)
            encoder.setBuffer(tqBuffer, offset: 0, index: 2)
            encoder.setBuffer(nbrBuffer, offset: 0, index: 3)
            encoder.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 4)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: perGroup)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

enum SimulationError: Error {
    case noQueue
    case missingFunction(String)
}
