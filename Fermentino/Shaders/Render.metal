//
//  Render.metal
//  Fermentino
//
//  Инстансированный рендер кругов: один draw call, квад на тело,
//  круг вырезается во фрагментном шейдере.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 local;
    float speed;
};

constant float2 quadCorners[6] = {
    float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
    float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
};

vertex VertexOut bodyVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            device const float2 *positions  [[buffer(0)]],
                            device const float2 *velocities [[buffer(1)]],
                            constant SimParams &p           [[buffer(2)]])
{
    const float2 corner = quadCorners[vid];
    const float2 world = positions[iid] + corner * p.radius * 1.15;

    VertexOut out;
    out.position = float4(world.x / p.aspect, world.y, 0.0, 1.0);
    out.local = corner;
    out.speed = length(velocities[iid]);
    return out;
}

fragment float4 bodyFragment(VertexOut in [[stage_in]])
{
    const float r = length(in.local);
    const float edge = fwidth(r) * 1.5;
    const float alpha = 1.0 - smoothstep(1.0 - edge, 1.0, r * 1.15);
    if (alpha <= 0.0) discard_fragment();

    const float t = saturate(in.speed * 0.6);
    const float3 slow = float3(0.25, 0.55, 1.0);
    const float3 fast = float3(1.0, 0.85, 0.3);
    const float3 color = mix(slow, fast, t);
    return float4(color * alpha, alpha);
}
