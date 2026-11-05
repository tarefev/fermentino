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
        // поворот на угол halfSize.x (звезда крутится вместе с хостом)
        const float sa = in.halfSize.x;
        const float sc = cos(sa), ss = sin(sa);
        const float2 q = float2(sc * in.local.x + ss * in.local.y, -ss * in.local.x + sc * in.local.y);
        const float d = sdStar5(float2(q.x, -q.y), in.radius, in.inner);
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

// MARK: - Фон: фактура жижи, привязанная к миру (движение читается по ней)

struct BgOut {
    float4 position [[position]];
    float2 pt;      // экранные точки
};

vertex BgOut bgVertex(uint vid [[vertex_id]], constant FrameUniforms &u [[buffer(1)]])
{
    // один треугольник на весь экран
    const float2 ndc = float2(vid == 1u ? 3.0 : -1.0, vid == 2u ? 3.0 : -1.0);
    BgOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.pt = float2((ndc.x * 0.5 + 0.5) * u.viewSize.x, (1.0 - (ndc.y * 0.5 + 0.5)) * u.viewSize.y);
    return out;
}

inline float bgHash(int2 c)
{
    uint h = uint(c.x) * 374761393u + uint(c.y) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= h >> 16;
    return float(h & 0xffffu) / 65535.0;
}

// value noise на решётке с шагом cell, тайлится с периодом мира (period = worldSize / cell узлов)
inline float bgNoise(float2 w, float cell, int period)
{
    const float2 q = w / cell;
    const float2 fl = floor(q);
    float2 f = q - fl;
    f = f * f * (3.0 - 2.0 * f);
    int2 i = int2(fl);
    i = int2(((i.x % period) + period) % period, ((i.y % period) + period) % period);
    const int2 j = int2((i.x + 1) % period, (i.y + 1) % period);
    const float a = bgHash(int2(i.x, i.y)), b = bgHash(int2(j.x, i.y));
    const float c = bgHash(int2(i.x, j.y)), d = bgHash(int2(j.x, j.y));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fragment float4 bgFragment(BgOut in [[stage_in]], constant FrameUniforms &u [[buffer(1)]])
{
    const float2 w = u.cam + (in.pt - u.viewSize * 0.5) / u.scale;
    const float ws = u.worldSize;
    // три масштаба разводов: крупные пятна, средние клочья, мелкая рябь
    const float n = 0.50 * bgNoise(w, 180.0, int(ws / 180.0))
                  + 0.32 * bgNoise(w, 60.0, int(ws / 60.0))
                  + 0.18 * bgNoise(w, 20.0, int(ws / 20.0));
    const float3 base = float3(0.020, 0.024, 0.039);     // #05060a
    const float3 tint = float3(0.085, 0.115, 0.175);
    float3 col = base + tint * pow(n, 1.6);
    // зерно: редкие круглые мягкие крупинки на решётке 6 единиц
    const float2 gs = w / 6.0;
    const float2 gq = floor(gs);
    const int gp = int(ws / 6.0);
    const float g = bgHash(int2(((int(gq.x) % gp) + gp) % gp, ((int(gq.y) % gp) + gp) % gp));
    if (g > 0.93) {
        const float gd = length(gs - gq - 0.5);
        col += float3(0.050, 0.062, 0.085) * (1.0 - smoothstep(0.12, 0.42, gd));
    }
    return float4(col, 1.0);
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
