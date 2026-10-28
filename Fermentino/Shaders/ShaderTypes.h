//
//  ShaderTypes.h
//  Fermentino
//
//  Структуры, общие для Swift и Metal. Только C-типы и simd.
//  Константы типов/флагов продублированы в Swift (Game/BodyTypes.swift) — держать в синхроне.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#define FERM_MAX_CORES 16
#define FERM_MAX_SLOTS 12

// Тело: ядро / инертон / якорь. Ядра идут первыми (индекс тела = индекс ядра).
typedef struct {
    simd_float2 pos;
    simd_float2 vel;
    float m;
    float r;
    unsigned int type;     // 0 core, 1 atom, 2 anchor
    unsigned int flags;    // 1 captured, 4 mine, 8 molCore
    float ang;             // ориентация ядра (рад)
    float angVel;
    float tq;              // накопленный за подшаг «угловой момент» (сумма ошибок слотов)
    unsigned int nbr;      // соседей в радиусе INSTAB_R (инертоны)
    float heat;            // вспышка выброса/взрыва, 1 → 0
    float kAngle;          // жёсткость угла этого ядра (per-atom)
    float cap;             // 0→1 белизна/усадка при поглощении
    float r0;              // радиус до поглощения
} Body;

typedef struct {
    unsigned int bodyCount;
    unsigned int coreCount;
    float hSub;            // длительность подшага
    float G;
    float EPS2;
    float CUT_START;
    float CUT_END;
    float K_REP;
    float V_STICK;
    float STICK_MIN;
    float BOND_DAMP;
    float K_ANGLE;
    float K_ANGLE_TORQUE;
    float ANG_DAMP;
    float MAX_SPEED;
    float VISCOSITY;
    float INSTAB_R;
    float bubbleR2;        // (R_CORE·GRAV_OFF_R_MULT)² — радиус антиграва вокруг хоста
    unsigned int gravBubbleOn;
    unsigned int pad0;
    simd_float2 worldSize;
    simd_float2 zonePos;
    float zoneMass;        // >0 после победы: чёрная дыра в центре поглотителя
    float pad1;
} SimParams;

// Рендер: инстанс фигуры в экранных точках.
typedef struct {
    simd_float2 center;
    float radius;
    float inner;           // кольцо: внутренний радиус (0 = сплошной круг)
    simd_float4 color;     // straight alpha
    simd_float2 halfSize;  // для прямоугольника
    unsigned int shape;    // 0 круг, 1 прямоугольник
    float soft;            // 0 резкий край, 1 радиальное затухание (свечение/градиент)
} ShapeInstance;

typedef struct {
    simd_float2 pos;
    simd_float4 color;
} LineVertex;

typedef struct {
    simd_float2 viewSize;  // в точках
} FrameUniforms;

#endif /* ShaderTypes_h */
