//
//  Simulation.metal
//  Fermentino
//
//  Перенос computeForces/integrate из веб-прототипа один в один.
//  Каждый поток считает силы на СВОЁ тело по всем остальным (симметричные формулы).
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

#define BODY_CORE   0u
#define BODY_ATOM   1u
#define BODY_ANCHOR 2u
#define FLAG_CAPTURED 1u

inline float wrapDelta(float d, float halfSize, float full)
{
    if (d > halfSize) return d - full;
    if (d < -halfSize) return d + full;
    return d;
}

inline float wrapAngle(float e) { return atan2(sin(e), cos(e)); }

inline float gravTaper(float r, constant SimParams &p)
{
    if (r <= p.CUT_START) return 1.0;
    if (r >= p.CUT_END) return 0.0;
    const float t = (r - p.CUT_START) / (p.CUT_END - p.CUT_START);
    return 1.0 - t * t * (3.0 - 2.0 * t);
}

// §2: гравитация + отталкивание + липкость + валентные связи (длина, угол) + чёрная дыра
kernel void computeForces(device const Body *bodies     [[buffer(0)]],
                          device float2 *accel          [[buffer(1)]],
                          device float *tqOut           [[buffer(2)]],
                          device uint *nbrOut           [[buffer(3)]],
                          device const int *bondSlot    [[buffer(4)]],
                          device const float *bondK     [[buffer(5)]],
                          device const float *bondLen   [[buffer(6)]],
                          device const float *slots     [[buffer(7)]],
                          constant SimParams &p         [[buffer(8)]],
                          uint i [[thread_position_in_grid]])
{
    if (i >= p.bodyCount) return;

    const Body A = bodies[i];
    const float2 hw = p.worldSize * 0.5;
    const float cutEnd2 = p.CUT_END * p.CUT_END;
    const float instR2 = p.INSTAB_R * p.INSTAB_R;
    const bool aCaptured = (A.flags & FLAG_CAPTURED) != 0;
    const bool aAnchor = A.type == BODY_ANCHOR;
    const bool aCore = A.type == BODY_CORE && i < p.coreCount;

    // пузырь антиграва: объект внутри радиуса вокруг хоста (тело 0)
    const float2 hostPos = bodies[0].pos;
    bool aGb = false;
    if (p.gravBubbleOn) {
        const float gx = wrapDelta(A.pos.x - hostPos.x, hw.x, p.worldSize.x);
        const float gy = wrapDelta(A.pos.y - hostPos.y, hw.y, p.worldSize.y);
        aGb = gx * gx + gy * gy <= p.bubbleR2;
    }

    float2 acc = float2(0.0);
    float tq = 0.0;
    uint nbr = 0;

    for (uint j = 0; j < p.bodyCount; ++j) {
        if (j == i) continue;
        const Body B = bodies[j];
        if (aCaptured && (B.flags & FLAG_CAPTURED)) continue;   // молекула не взаимодействует сама с собой

        const float dx = wrapDelta(B.pos.x - A.pos.x, hw.x, p.worldSize.x);
        const float dy = wrapDelta(B.pos.y - A.pos.y, hw.y, p.worldSize.y);
        float r2 = dx * dx + dy * dy;
        if (r2 > cutEnd2) continue;
        if (A.type == BODY_ATOM && B.type == BODY_ATOM && r2 < instR2) nbr++;
        if (r2 < 1e-6) r2 = 1e-6;

        const float r = sqrt(r2);
        const float inv = 1.0 / r;
        const float nx = dx * inv, ny = dy * inv;
        const float mm = A.m * B.m;

        bool bGb = false;
        if (p.gravBubbleOn) {
            const float gx = wrapDelta(B.pos.x - hostPos.x, hw.x, p.worldSize.x);
            const float gy = wrapDelta(B.pos.y - hostPos.y, hw.y, p.worldSize.y);
            bGb = gx * gx + gy * gy <= p.bubbleR2;
        }
        const float gOn = (p.gravBubbleOn && (aGb || bGb)) ? 0.0 : 1.0;
        float fnet = gOn * p.G * mm / (r2 + p.EPS2) * gravTaper(r, p);

        const float contact = A.r + B.r;
        if (r < contact) {
            const float mu = mm / (A.m + B.m);
            fnet -= p.K_REP * mu * (contact - r);
            if (!aAnchor && B.type != BODY_ANCHOR) {
                const float vn = (A.vel.x - B.vel.x) * nx + (A.vel.y - B.vel.y) * ny;
                float stick = 1.0;
                if (p.V_STICK > 0.0) stick = 1.0 - (1.0 - p.STICK_MIN) * exp(-abs(vn) / p.V_STICK);
                fnet -= stick * mu * vn / p.hSub;
            }
        }

        if (aCore && B.type == BODY_CORE && j < p.coreCount) {
            const int sA = bondSlot[i * FERM_MAX_CORES + j];
            if (sA >= 0) {
                const int sB = bondSlot[j * FERM_MAX_CORES + i];
                const float k = bondK[i * FERM_MAX_CORES + j];
                const float len = bondLen[i * FERM_MAX_CORES + j];
                const float L = contact * len;
                const float mu = mm / (A.m + B.m);
                const float vn = (A.vel.x - B.vel.x) * nx + (A.vel.y - B.vel.y) * ny;
                fnet += k * mu * (r - L) - p.BOND_DAMP * mu * vn;
                const float phi = atan2(dy, dx);
                const float eA = wrapAngle(phi - (A.ang + slots[i * FERM_MAX_SLOTS + sA]));
                const float eB = wrapAngle(phi + M_PI_F - (B.ang + slots[j * FERM_MAX_SLOTS + sB]));
                tq += eA;
                const float px = -ny, py = nx;
                const float vtB = (B.vel.x - A.vel.x) * px + (B.vel.y - A.vel.y) * py;
                const float fB = -mu * (A.kAngle * eA + B.kAngle * eB) - p.BOND_DAMP * mu * vtB;   // per-atom жёсткость угла
                acc -= float2(px, py) * (fB / A.m);           // реакция на A (поперечная)
            }
        }

        if (!aAnchor) acc += float2(nx, ny) * (fnet / A.m);
    }

    // чёрная дыра в центре поглотителя (после победы)
    if (p.zoneMass > 0.0 && !aAnchor && !aCaptured) {
        const float dx = wrapDelta(p.zonePos.x - A.pos.x, hw.x, p.worldSize.x);
        const float dy = wrapDelta(p.zonePos.y - A.pos.y, hw.y, p.worldSize.y);
        float r2 = dx * dx + dy * dy;
        if (r2 <= cutEnd2) {
            if (r2 < 1e-6) r2 = 1e-6;
            const float r = sqrt(r2), inv = 1.0 / r;
            const float a = p.G * p.zoneMass / (r2 + p.EPS2) * gravTaper(r, p);
            acc += float2(dx, dy) * (a * inv);
        }
    }

    accel[i] = acc;
    tqOut[i] = tq;
    nbrOut[i] = nbr;
}

// §3: симплектик Эйлер-Кромер + вязкость + потолок скорости + ориентация ядер
kernel void integrate(device Body *bodies           [[buffer(0)]],
                      device const float2 *accel    [[buffer(1)]],
                      device const float *tqIn      [[buffer(2)]],
                      device const uint *nbrIn      [[buffer(3)]],
                      constant SimParams &p         [[buffer(4)]],
                      uint i [[thread_position_in_grid]])
{
    if (i >= p.bodyCount) return;
    Body o = bodies[i];
    o.nbr = nbrIn[i];
    o.tq = tqIn[i];
    if (o.type != BODY_ANCHOR) {
        const float h = p.hSub;
        o.vel += accel[i] * h;
        o.vel *= exp(-p.VISCOSITY * h);
        const float s2 = dot(o.vel, o.vel);
        const float cap2 = p.MAX_SPEED * p.MAX_SPEED;
        if (s2 > cap2) o.vel *= p.MAX_SPEED / sqrt(s2);
        o.pos += o.vel * h;
        if (o.type == BODY_CORE) {
            o.angVel += p.K_ANGLE_TORQUE * o.tq * h;
            o.angVel *= max(0.0, 1.0 - p.ANG_DAMP * h);
            o.ang += o.angVel * h;
        }
    }
    bodies[i] = o;
}
