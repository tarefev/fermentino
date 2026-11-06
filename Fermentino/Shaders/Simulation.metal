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
#define BODY_DUST   3u   // физика как у инертона, в логике не участвует
#define FLAG_CAPTURED 1u
#define FLAG_HELD     16u   // ядро комка: прибито к концу щупа
#define FLAG_MEMBER   32u   // зерно комка: держится притяжением конца своего щупа и контактом
#define FLAG_GROUP    48u
#define FLAG_APPLE    64u   // «яблоко»: заряд другого сорта — камни его не чувствуют, тянет его только рука в режиме яблок
#define BODY_TIP    4u

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
                          device const float *probeMass [[buffer(9)]],
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
        if (r2 < instR2) {
            // соседи нестабильности: инертон считает инертоны; пыль считает пыль и инертоны
            if (A.type == BODY_ATOM && B.type == BODY_ATOM) nbr++;
            if (A.type == BODY_DUST && (B.type == BODY_DUST || B.type == BODY_ATOM)) nbr++;
        }
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
        // тело на щупе притягивает слабее: его гравитационная масса умножена на heldGravity (инерция прежняя)
        float gA = A.m, gB = B.m;
        if (p.holdOn != 0u) {
            if (i == 0u) gA *= p.hostGravity;      // корабль притягивает слабее: тянут концы свободных щупов
            if (j == 0u) gB *= p.hostGravity;
            if ((A.flags & FLAG_GROUP) != 0u) gA *= p.heldGravity;
            if ((B.flags & FLAG_GROUP) != 0u) gB *= p.heldGravity;
        }
        // проба «заряд»: два камня (пыль или инертон, кроме ядрышек на концах щупалец) действуют друг на друга
        // с множителем rockForce — при отрицательном отталкиваются. Все остальные пары — как раньше.
        float pairSign = 1.0;
        const bool aRock = (A.type == BODY_DUST || A.type == BODY_ATOM) && (A.flags & FLAG_HELD) == 0u;
        const bool bRock = (B.type == BODY_DUST || B.type == BODY_ATOM) && (B.flags & FLAG_HELD) == 0u;
        // камни и яблоки несут заряды разного сорта: одноимённые действуют друг на друга (rockForce),
        // разноимённые друг друга не чувствуют; ядрышко на конце щупальца тянет только камни
        const bool aApple = (A.flags & FLAG_APPLE) != 0u, bApple = (B.flags & FLAG_APPLE) != 0u;
        if (aRock && bRock) pairSign = (aApple == bApple) ? p.rockForce : 0.0;
        if ((aApple && B.type == BODY_TIP) || (bApple && A.type == BODY_TIP)) pairSign = 0.0;
        float fnet = gOn * pairSign * p.G * gA * gB / (r2 + p.EPS2) * gravTaper(r, p);

        const float contact = A.r + B.r;
        if (r < contact) {
            const float mu = mm / (A.m + B.m);
            fnet -= p.K_REP * mu * (contact - r);
            // хост при захвате по щупам отбивает ИНЕРТОНЫ упруго (не налипают на шар);
            // пыль об него вязнет, как обо всё остальное, иначе её вечно швыряет отскоком
            const bool hostElastic = p.holdOn != 0u
                && ((i == 0u && B.type == BODY_ATOM) || (j == 0u && A.type == BODY_ATOM));
            // к комку на щупе ничего не прилипает: контакт «держится — свободное» упругий
            const bool aHeldC = (A.flags & FLAG_GROUP) != 0u, bHeldC = (B.flags & FLAG_GROUP) != 0u;
            const bool heldElastic = p.holdOn != 0u && (aHeldC != bHeldC) && i != 0u && j != 0u;
            if (!aAnchor && B.type != BODY_ANCHOR && !hostElastic && !heldElastic) {
                const float vn = (A.vel.x - B.vel.x) * nx + (A.vel.y - B.vel.y) * ny;
                float stick = 1.0;
                if (p.V_STICK > 0.0) stick = 1.0 - (1.0 - p.STICK_MIN) * exp(-abs(vn) / p.V_STICK);
                fnet -= stick * mu * vn / p.hSub;
            }
        }

        // щуп: связь хост — тело на щупе. Тело помнит своё место в системе хоста: длину покоя (в angVel)
        // и угол покоя относительно ориентации хоста (в ang) — так на одном щупе держится целый комок.
        if (p.holdOn != 0u) {
            const bool aHeld = (A.flags & FLAG_HELD) != 0u, bHeld = (B.flags & FLAG_HELD) != 0u;
            if ((i == 0u && bHeld) || (j == 0u && aHeld)) {
                const float L = (i == 0u) ? B.angVel : A.angVel;
                const float restAng = (i == 0u) ? B.ang : A.ang;
                const float mu = mm / (A.m + B.m);
                const float vn = (A.vel.x - B.vel.x) * nx + (A.vel.y - B.vel.y) * ny;
                fnet += p.holdK * mu * (r - L) - p.holdDamp * mu * vn;
                const float phi = atan2(dy, dx);
                const float px = -ny, py = nx;
                const float vtB = (B.vel.x - A.vel.x) * px + (B.vel.y - A.vel.y) * py;
                float fB = 0.0;
                if (i == 0u) {
                    const float eHost = wrapAngle(phi - (A.ang + restAng));
                    fB = -mu * (A.kAngle * eHost) - p.holdDamp * mu * vtB;
                } else {
                    const float eHost = wrapAngle(phi + M_PI_F - (B.ang + restAng));
                    fB = -mu * (B.kAngle * eHost) - p.holdDamp * mu * vtB;
                }
                acc -= float2(px, py) * (fB / A.m);
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

        // концы щупов притягивают тело B; хост получает равную противоположную силу.
        // Зерно комка тянет только конец ЕГО щупа (полной силой), свободное тело — все щупы по их текущей массе.
        if (i == 0u && p.holdOn != 0u && B.type != BODY_ANCHOR
            && (B.flags & (FLAG_CAPTURED | FLAG_HELD)) == 0u) {
            const bool member = (B.flags & FLAG_MEMBER) != 0u;
            const int ownSlot = int(B.kAngle);
            for (int s = 0; s < int(FERM_MAX_SLOTS); ++s) {
                float pm = probeMass[s];
                if (member) pm = (s == ownSlot) ? p.memberPull : 0.0;
                else {
                    // знак массы щупальца — его режим: плюс тянет камни, минус — только яблоки
                    const bool apple = (B.flags & FLAG_APPLE) != 0u;
                    if (pm < 0.0) pm = apple ? -pm : 0.0;
                    else if (apple) pm = 0.0;
                }
                if (pm <= 0.0) continue;
                const float ta = A.ang + slots[s];
                const float2 tip = A.pos + float2(cos(ta), sin(ta)) * p.holdLen;
                const float tx = wrapDelta(tip.x - B.pos.x, hw.x, p.worldSize.x);
                const float ty = wrapDelta(tip.y - B.pos.y, hw.y, p.worldSize.y);
                float tr2 = tx * tx + ty * ty;
                if (tr2 > cutEnd2) continue;
                if (tr2 < 1e-6) tr2 = 1e-6;
                const float tr = sqrt(tr2);
                const float ta2 = p.G * pm / (tr2 + p.EPS2) * gravTaper(tr, p);   // ускорение B к концу щупа
                acc -= float2(tx, ty) * (ta2 / tr) * (B.m / A.m);                  // реакция на корабль
            }
        }
    }

    // конец щупа притягивает это тело (зерно комка — только свой щуп, свободное — все)
    if (i != 0u && p.holdOn != 0u && !aAnchor && (A.flags & (FLAG_CAPTURED | FLAG_HELD)) == 0u) {
        const Body H = bodies[0];
        const bool member = (A.flags & FLAG_MEMBER) != 0u;
        const int ownSlot = int(A.kAngle);
        for (int s = 0; s < int(FERM_MAX_SLOTS); ++s) {
            float pm = probeMass[s];
            if (member) pm = (s == ownSlot) ? p.memberPull : 0.0;
            else {
                const bool apple = (A.flags & FLAG_APPLE) != 0u;
                if (pm < 0.0) pm = apple ? -pm : 0.0;
                else if (apple) pm = 0.0;
            }
            if (pm <= 0.0) continue;
            const float ta = H.ang + slots[s];
            const float2 tip = H.pos + float2(cos(ta), sin(ta)) * p.holdLen;
            const float tx = wrapDelta(tip.x - A.pos.x, hw.x, p.worldSize.x);
            const float ty = wrapDelta(tip.y - A.pos.y, hw.y, p.worldSize.y);
            float tr2 = tx * tx + ty * ty;
            if (tr2 > cutEnd2) continue;
            if (tr2 < 1e-6) tr2 = 1e-6;
            const float tr = sqrt(tr2);
            const float ta2 = p.G * pm / (tr2 + p.EPS2) * gravTaper(tr, p);
            acc += float2(tx, ty) * (ta2 / tr);
        }
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
        // проба «тепло»: среда не только тормозит, но и толкает (броуновское движение). Толчок обратно
        // пропорционален корню из массы; корабль, ядрышки и втянутое в поглотитель не трогаем.
        if (p.thermalKick > 0.0 && i != 0u && (o.flags & (FLAG_CAPTURED | FLAG_HELD)) == 0u) {
            uint hsh = i * 747796405u + p.seed * 2891336453u + 12345u;
            hsh = ((hsh >> ((hsh >> 28u) + 4u)) ^ hsh) * 277803737u; hsh = (hsh >> 22u) ^ hsh;
            const float u1 = max(float(hsh & 0xFFFFFFu) / 16777216.0, 1e-6);
            hsh = hsh * 747796405u + 2891336453u;
            hsh = ((hsh >> ((hsh >> 28u) + 4u)) ^ hsh) * 277803737u; hsh = (hsh >> 22u) ^ hsh;
            const float u2 = float(hsh & 0xFFFFFFu) / 16777216.0;
            const float mag = sqrt(-2.0 * log(u1)) * p.thermalKick * sqrt(150.0 / max(o.m, 1.0));
            o.vel += float2(cos(6.2831853 * u2), sin(6.2831853 * u2)) * mag;
        }
        const float s2 = dot(o.vel, o.vel);
        const float cap2 = p.MAX_SPEED * p.MAX_SPEED;
        if (s2 > cap2) o.vel *= p.MAX_SPEED / sqrt(s2);
        o.pos += o.vel * h;
        if (o.type == BODY_CORE) {
            if (i == 0u && p.holdOn != 0u) {
                // хост со щупами вращается только с заданной скоростью: удары и рывки на угол не влияют
                o.angVel = 0.0;
                o.ang += p.hostSpin * h;
            } else {
                o.angVel += p.K_ANGLE_TORQUE * o.tq * h;
                o.angVel *= max(0.0, 1.0 - p.ANG_DAMP * h);
                o.ang += o.angVel * h;
            }
        }
    }
    bodies[i] = o;
}
