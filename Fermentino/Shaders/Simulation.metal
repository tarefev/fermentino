//
//  Simulation.metal
//  Fermentino
//
//  Симуляция на GPU: попарная гравитация, предикт, расталкивание через
//  хэш-сетку (position-based), восстановление скорости из смещения.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

constant uint TILE = 256;

// MARK: - 1. Очистка сетки

kernel void clearGrid(device atomic_uint *cellCounts [[buffer(0)]],
                      constant SimParams &p        [[buffer(1)]],
                      uint id [[thread_position_in_grid]])
{
    if (id >= p.gridDims.x * p.gridDims.y) return;
    atomic_store_explicit(&cellCounts[id], 0u, memory_order_relaxed);
}

// MARK: - 2. Гравитация «каждый с каждым», тайлинг через threadgroup-память

kernel void computeGravity(device const float2 *positions [[buffer(0)]],
                           device float2 *accelerations    [[buffer(1)]],
                           constant SimParams &p           [[buffer(2)]],
                           uint id  [[thread_position_in_grid]],
                           uint lid [[thread_position_in_threadgroup]])
{
    threadgroup float2 tile[TILE];

    const bool active = id < p.bodyCount;
    float2 pos = active ? positions[id] : float2(0.0);
    float2 acc = float2(0.0);

    const uint tileCount = (p.bodyCount + TILE - 1) / TILE;
    for (uint t = 0; t < tileCount; ++t) {
        const uint j = t * TILE + lid;
        tile[lid] = (j < p.bodyCount) ? positions[j] : float2(0.0);
        threadgroup_barrier(mem_flags::mem_threadgroup);

        const uint limit = min(TILE, p.bodyCount - t * TILE);
        for (uint k = 0; k < limit; ++k) {
            const float2 d = tile[k] - pos;
            const float r2 = dot(d, d) + p.softening;
            const float inv = rsqrt(r2);
            acc += d * (inv * inv * inv);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (!active) return;

    acc *= p.gravity;

    if (p.attractorStrength > 0.0) {
        const float2 d = p.attractor - pos;
        const float r2 = dot(d, d) + p.softening * 16.0;
        const float inv = rsqrt(r2);
        acc += d * (inv * inv * inv) * p.attractorStrength;
    }

    accelerations[id] = acc;
}

// MARK: - 3. Предикт позиции и вставка в сетку

inline uint2 cellOf(float2 pos, constant SimParams &p)
{
    const float2 local = (pos + p.worldHalf) / p.cellSize;
    const int2 c = int2(floor(local));
    return uint2(clamp(c.x, 0, int(p.gridDims.x) - 1),
                 clamp(c.y, 0, int(p.gridDims.y) - 1));
}

kernel void integrate(device float2 *positions          [[buffer(0)]],
                      device float2 *previousPositions  [[buffer(1)]],
                      device float2 *velocities         [[buffer(2)]],
                      device const float2 *accelerations [[buffer(3)]],
                      device atomic_uint *cellCounts    [[buffer(4)]],
                      device uint *cellItems            [[buffer(5)]],
                      constant SimParams &p             [[buffer(6)]],
                      uint id [[thread_position_in_grid]])
{
    if (id >= p.bodyCount) return;

    float2 pos = positions[id];
    float2 vel = velocities[id] + accelerations[id] * p.dt;
    vel *= p.damping;

    previousPositions[id] = pos;
    pos += vel * p.dt;

    // стены: отражаем скорость через позицию (PBD)
    const float2 lim = p.worldHalf - p.radius;
    pos = clamp(pos, -lim, lim);
    positions[id] = pos;

    const uint2 c = cellOf(pos, p);
    const uint cell = c.y * p.gridDims.x + c.x;
    const uint slot = atomic_fetch_add_explicit(&cellCounts[cell], 1u, memory_order_relaxed);
    if (slot < p.cellCapacity) {
        cellItems[cell * p.cellCapacity + slot] = id;
    }
}

// MARK: - 4. Расталкивание по сетке (ping-pong позиций)

kernel void resolveCollisions(device const float2 *positionsIn [[buffer(0)]],
                              device float2 *positionsOut      [[buffer(1)]],
                              device const atomic_uint *cellCounts [[buffer(2)]],
                              device const uint *cellItems     [[buffer(3)]],
                              constant SimParams &p            [[buffer(4)]],
                              uint id [[thread_position_in_grid]])
{
    if (id >= p.bodyCount) return;

    const float2 pos = positionsIn[id];
    const float diameter = p.radius * 2.0;
    const float diameter2 = diameter * diameter;
    float2 correction = float2(0.0);

    const uint2 c = cellOf(pos, p);
    const int2 base = int2(c);

    for (int dy = -1; dy <= 1; ++dy) {
        const int cy = base.y + dy;
        if (cy < 0 || cy >= int(p.gridDims.y)) continue;
        for (int dx = -1; dx <= 1; ++dx) {
            const int cx = base.x + dx;
            if (cx < 0 || cx >= int(p.gridDims.x)) continue;

            const uint cell = uint(cy) * p.gridDims.x + uint(cx);
            const uint count = min(atomic_load_explicit(&cellCounts[cell], memory_order_relaxed),
                                   p.cellCapacity);
            for (uint s = 0; s < count; ++s) {
                const uint j = cellItems[cell * p.cellCapacity + s];
                if (j == id) continue;
                const float2 d = pos - positionsIn[j];
                const float r2 = dot(d, d);
                if (r2 >= diameter2 || r2 < 1e-12) continue;
                const float dist = sqrt(r2);
                const float overlap = diameter - dist;
                correction += d * (overlap * 0.5 / dist);
            }
        }
    }

    const float2 lim = p.worldHalf - p.radius;
    positionsOut[id] = clamp(pos + correction, -lim, lim);
}

// MARK: - 5. Скорость из смещения за подшаг

kernel void finalizeVelocity(device const float2 *positions         [[buffer(0)]],
                             device const float2 *previousPositions [[buffer(1)]],
                             device float2 *velocities              [[buffer(2)]],
                             constant SimParams &p                  [[buffer(3)]],
                             uint id [[thread_position_in_grid]])
{
    if (id >= p.bodyCount) return;
    const float2 vel = (positions[id] - previousPositions[id]) / p.dt;
    velocities[id] = vel * p.restitutionDamping;
}
