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

// шум для ржавчины на корпусе корабля: хеш → плавный шум → четыре октавы
inline float hullHash(float2 p)
{
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

inline float hullNoise(float2 p)
{
    const float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    const float a = hullHash(i), b = hullHash(i + float2(1.0, 0.0));
    const float c = hullHash(i + float2(0.0, 1.0)), d = hullHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

inline float hullFbm(float2 p)
{
    float sum = 0.0, amp = 0.5;
    for (int k = 0; k < 4; ++k) { sum += amp * hullNoise(p); amp *= 0.5; p *= 2.1; }
    return sum;
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
    if (s.shape == 3u || s.shape == 4u || s.shape == 5u) ext = float2(s.radius + 2.0);
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
    float3 rgb = in.color.rgb;
    if (in.shape == 4u) {
        // правильный многоугольник вершиной вверх: максимум по нормалям сторон
        const int n = int(in.inner);
        const float apothem = in.radius * cos(M_PI_F / float(n));
        float d = -1e9;
        for (int k = 0; k < n; ++k) {
            const float phi = -M_PI_F * 0.5 + M_PI_F / float(n) + float(k) * 2.0 * M_PI_F / float(n);
            d = max(d, dot(in.local, float2(cos(phi), sin(phi))) - apothem);
        }
        const float edge = max(fwidth(d), 0.5);
        a = 1.0 - smoothstep(-edge, edge, d);
    } else if (in.shape == 3u) {
        // стрелка компаса: плоский клин с тупым углом наружу (+x после поворота), сторона к кораблю — дуга
        // вокруг него. radius = полуширина, inner = высота клина, halfSize = (угол, расстояние до центра корабля)
        const float ang = in.halfSize.x;
        const float c = cos(ang), s = sin(ang);
        const float2 p = float2(c * in.local.x + s * in.local.y, -s * in.local.x + c * in.local.y);
        const float w = in.radius, h = in.inner, ringR = in.halfSize.y;
        // внутренняя сторона: дуга радиуса ringR с центром в корабле, проходит через начало координат;
        // углы клина лежат на этой дуге на полуширине w
        const float xc = sqrt(max(ringR * ringR - w * w, 0.0)) - ringR;
        const float2 nUp = normalize(float2(w, h - xc));  // нормали двух прямых сторон, сходящихся в острие (h, 0)
        const float2 nDn = normalize(float2(w, xc - h));
        const float d1 = dot(p - float2(h, 0.0), nUp);
        const float d2 = dot(p - float2(h, 0.0), nDn);
        const float d3 = ringR - length(p - float2(-ringR, 0.0));
        const float d = max(max(d1, d2), d3);
        const float edge = max(fwidth(d), 0.5);
        a = 1.0 - smoothstep(-edge, edge, d);
    } else if (in.shape == 5u) {
        // метка на ободе: кусок кольца между двумя концентрическими дугами (inner и radius) с прямыми
        // параллельными боками. halfSize = (угол оси, полуширина)
        const float ang = in.halfSize.x;
        const float2 axis = float2(cos(ang), sin(ang));
        const float along = dot(in.local, axis);
        const float across = abs(dot(in.local, float2(-axis.y, axis.x)));
        const float d = length(in.local);
        const float edge = max(fwidth(d), 0.5);
        a = (1.0 - smoothstep(in.radius - edge, in.radius + edge, d))
          * smoothstep(in.inner - edge, in.inner + edge, d)
          * (1.0 - smoothstep(in.halfSize.y - edge, in.halfSize.y + edge, across))
          * step(0.0, along);
    } else if (in.shape == 6u) {
        // корпус корабля: ржавый железный шар со швами и заклёпками. halfSize = (угол поворота корабля,
        // сила ржавчины 0…1). При силе 0 это ровный круг цвета color — корабль «включился».
        const float d = length(in.local);
        const float edge = max(fwidth(d), 0.5);
        a = 1.0 - smoothstep(in.radius - edge, in.radius + edge, d);
        const float k = in.halfSize.y;
        if (k > 0.0) {
            const float sa = in.halfSize.x;
            const float sc = cos(sa), ss = sin(sa);
            // q — точка в долях радиуса, в осях корабля: рисунок вращается вместе с ним
            const float2 q = float2(sc * in.local.x + ss * in.local.y, -ss * in.local.x + sc * in.local.y) / in.radius;
            const float qd = length(q);
            float3 col = rgb;
            // рыжие разводы ржавчины
            const float n = hullFbm(q * 3.2 + float2(7.0, 3.0));
            col = mix(col, float3(0.604, 0.298, 0.125), saturate((n - 0.45) * 2.5));
            // объём: борт темнее, сверху слева блик (свет неподвижен, с кораблём не вращается)
            col *= 1.0 - 0.5 * qd * qd * qd;
            const float ht = saturate(1.0 - length(in.local / in.radius - float2(-0.32, -0.34)) / 0.75);
            col = mix(col, float3(0.690, 0.478, 0.333), 0.4 * ht * ht);
            // швы: кольцевой и крест внутри него; не тоньше полутора пикселей
            const float w = max(0.035, 0.5 / in.radius);
            float seam = abs(qd - 0.74);
            if (qd < 0.74) seam = min(seam, min(abs(q.x), abs(q.y)));
            col = mix(col, float3(0.141, 0.075, 0.047), saturate(1.0 - seam / w));
            // двенадцать заклёпок по борту
            const float seg = M_PI_F / 6.0;
            const float ra = (floor(atan2(q.y, q.x) / seg) + 0.5) * seg;
            const float rv = length(q - 0.87 * float2(cos(ra), sin(ra)));
            col = mix(col, float3(0.851, 0.647, 0.486), saturate(1.0 - rv / 0.055));
            rgb = mix(rgb, col, k);
        }
    } else if (in.shape == 2u) {
        // звезда остриём вверх (экранный y вниз → переворачиваем)
        // поворот на угол halfSize.x (звезда крутится вместе с хостом)
        const float sa = in.halfSize.x;
        const float sc = cos(sa), ss = sin(sa);
        const float2 q = float2(sc * in.local.x + ss * in.local.y, -ss * in.local.x + sc * in.local.y);
        const float d = sdStar5(float2(q.x, -q.y), in.radius, in.inner);
        const float edge = max(fwidth(d), 0.5);
        a = 1.0 - smoothstep(-edge, edge, d);
        // небольшой градиент вдоль главного луча (halfSize.y — сила): кончик луча своего цвета,
        // к противоположной стороне звезда уходит в тёмно-оранжевый — так видно, куда она смотрит
        if (in.halfSize.y > 0.0) {
            const float back = saturate(0.5 + 0.5 * q.y / in.radius);     // 0 у кончика главного луча, 1 сзади
            rgb = mix(rgb, rgb * float3(0.60, 0.24, 0.12), in.halfSize.y * back);
        }
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
    return float4(rgb * alpha, alpha);
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
    return float(h & 0xffffffu) / 16777215.0;
}

inline int2 bgWrap(int2 i, int period)
{
    return int2(((i.x % period) + period) % period, ((i.y % period) + period) % period);
}

// единичный градиент в узле решётки
inline float2 bgGrad(int2 i, int period)
{
    const float a = bgHash(bgWrap(i, period)) * 6.2831853;
    return float2(cos(a), sin(a));
}

// градиентный шум (Перлин) с шагом cell, тайлится с периодом мира; значение примерно в [-1, 1]
inline float bgPerlin(float2 w, float cell, int period)
{
    const float2 q = w / cell;
    const float2 fl = floor(q);
    const float2 f = q - fl;
    const int2 i = int2(fl);
    const float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // плавность до второй производной: без граней
    const float a = dot(bgGrad(i, period), f);
    const float b = dot(bgGrad(i + int2(1, 0), period), f - float2(1.0, 0.0));
    const float c = dot(bgGrad(i + int2(0, 1), period), f - float2(0.0, 1.0));
    const float d = dot(bgGrad(i + int2(1, 1), period), f - float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.41;
}

// цвет фактуры жижи в мировой точке w0 (разводы, без зерна)
inline float3 bgLiquid(float2 w0, float ws)
{
    // искажение координат: разводы текут, а не лежат по осям решётки
    const float2 warp = float2(bgPerlin(w0 + float2(310.0, 90.0), 300.0, int(ws / 300.0)),
                               bgPerlin(w0 + float2(40.0, 700.0), 300.0, int(ws / 300.0)));
    const float2 w = w0 + warp * 70.0;
    // четыре октавы: от крупных пятен до мелкой ряби
    float n = 0.50 * bgPerlin(w, 240.0, int(ws / 240.0))
            + 0.27 * bgPerlin(w, 120.0, int(ws / 120.0))
            + 0.15 * bgPerlin(w, 60.0, int(ws / 60.0))
            + 0.08 * bgPerlin(w, 30.0, int(ws / 30.0));
    n = saturate(n * 0.5 + 0.5);
    const float3 base = float3(0.020, 0.024, 0.039);     // #05060a
    const float3 tint = float3(0.075, 0.105, 0.165);
    return base + tint * smoothstep(0.25, 0.85, n);
}

// Запекание фактуры в текстуру один раз при запуске: текстура покрывает весь тор-мир и тайлится.
// Считать шум на каждый пиксель каждый кадр слишком дорого для телефона.
kernel void bakeBackground(texture2d<float, access::write> outTex [[texture(0)]],
                           constant FrameUniforms &u               [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    const float2 w0 = (float2(gid) + 0.5) / float2(outTex.get_width(), outTex.get_height()) * u.worldSize;
    outTex.write(float4(bgLiquid(w0, u.worldSize), 1.0), gid);
}

fragment float4 bgFragment(BgOut in [[stage_in]],
                           constant FrameUniforms &u [[buffer(1)]],
                           texture2d<float> liquid   [[texture(0)]])
{
    constexpr sampler smp(address::repeat, filter::linear);
    // экран = центр + R(viewRot)·(мир − камера)·scale → обратно: поворачиваем смещение пикселя на −viewRot
    const float2 dpt = in.pt - u.viewSize * 0.5;
    const float vc = cos(u.viewRot), vs = sin(u.viewRot);
    const float2 w0 = u.cam + float2(vc * dpt.x + vs * dpt.y, -vs * dpt.x + vc * dpt.y) / u.scale;
    const float ws = u.worldSize;
    float3 col = liquid.sample(smp, w0 / ws).rgb;
    // зерно: мягкие крупинки со случайным сдвигом и размером внутри ячейки — сетка не читается (дёшево: три хэша)
    const float cellG = 9.0;
    const float2 gs = w0 / cellG;
    const float2 gq = floor(gs);
    const int gp = int(ws / cellG);
    const int2 gi = bgWrap(int2(gq), gp);
    const float g = bgHash(gi);
    if (g > 0.45) {
        const float2 off = float2(bgHash(gi + int2(17, 3)), bgHash(gi + int2(5, 29))) * 0.6 + 0.2;
        const float rad = 0.05 + 0.09 * bgHash(gi + int2(41, 11));
        const float gd = length(gs - gq - off);
        col += float3(0.055, 0.068, 0.095) * (1.0 - smoothstep(rad * 0.4, rad, gd)) * (0.4 + 0.6 * g);
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
