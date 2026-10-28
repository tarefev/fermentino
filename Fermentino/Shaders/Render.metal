//
//  Render.metal
//  Fermentino
//
//  Инстансированные фигуры (круг/кольцо/прямоугольник/свечение) и линии в экранных точках.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

constant float2 quadCorners[6] = {
    float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
    float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
};

struct ShapeOut {
    float4 position [[position]];
    float2 local;
    float4 color;
    float radius;
    float inner;
    float soft;
    float2 halfSize;
    uint shape;
};

// SDF пятиконечной звезды (iq): r — внешний радиус, rf — отношение внутреннего к внешнему
inline float sdStar5(float2 p, float r, float rf)
{
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    const float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    const float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

inline float4 toNDC(float2 pt, constant FrameUniforms &u)
{
    float2 ndc = pt / u.viewSize * 2.0 - 1.0;
    ndc.y = -ndc.y;
    return float4(ndc, 0.0, 1.0);
}

vertex ShapeOut shapeVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            device const ShapeInstance *inst [[buffer(0)]],
                            constant FrameUniforms &u        [[buffer(1)]])
{
    const ShapeInstance s = inst[iid];
    const float2 corner = quadCorners[vid];
    float2 ext = float2(s.radius + 1.0);
    if (s.shape == 1u) ext = s.halfSize;
    if (s.shape == 3u) ext = float2(s.radius + 2.0);
    const float2 local = corner * ext;

    ShapeOut out;
    out.position = toNDC(s.center + local, u);
    out.local = local;
    out.color = s.color;
    out.radius = s.radius;
    out.inner = s.inner;
    out.soft = s.soft;
    out.halfSize = s.halfSize;
    out.shape = s.shape;
    return out;
}

fragment float4 shapeFragment(ShapeOut in [[stage_in]])
{
    float a = 1.0;
    if (in.shape == 3u) {
        // стрелка: остриё в +x локальной системы, повёрнутой на угол halfSize.x
        const float ang = in.halfSize.x;
        const float c = cos(ang), s = sin(ang);
        const float2 p = float2(c * in.local.x + s * in.local.y, -s * in.local.x + c * in.local.y);
        const float r = in.radius;
        const float back = -0.7 * r;                       // основание
        const float halfW = 0.6 * r * (r - p.x) / (r - back); // полуширина в точке p.x
        const float d = max(max(back - p.x, p.x - r), abs(p.y) - halfW);
        const float edge = max(fwidth(d), 0.5);
        a = 1.0 - smoothstep(-edge, edge, d);
    } else if (in.shape == 2u) {
        // звезда остриём вверх (экранный y вниз → переворачиваем)
        const float d = sdStar5(float2(in.local.x, -in.local.y), in.radius, in.inner);
        const float edge = max(fwidth(d), 0.5);
        a = 1.0 - smoothstep(-edge, edge, d);
    } else if (in.shape == 0u) {
        const float d = length(in.local);
        const float edge = max(fwidth(d), 0.5);
        if (in.soft > 0.0) {
            const float t = saturate(1.0 - d / in.radius);
            a = t * t;
        } else {
            a = 1.0 - smoothstep(in.radius - edge, in.radius + edge, d);
            if (in.inner > 0.0) a *= smoothstep(in.inner - edge, in.inner + edge, d);
        }
    }
    const float alpha = in.color.a * a;
    if (alpha <= 0.001) discard_fragment();
    return float4(in.color.rgb * alpha, alpha);
}

struct LineOut {
    float4 position [[position]];
    float4 color;
};

vertex LineOut lineVertex(uint vid [[vertex_id]],
                          device const LineVertex *verts [[buffer(0)]],
                          constant FrameUniforms &u      [[buffer(1)]])
{
    LineOut out;
    out.position = toNDC(verts[vid].pos, u);
    out.color = verts[vid].color;
    return out;
}

fragment float4 lineFragment(LineOut in [[stage_in]])
{
    return float4(in.color.rgb * in.color.a, in.color.a);
}
