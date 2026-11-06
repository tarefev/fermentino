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
    unsigned int type;     // 0 core, 1 atom, 2 anchor, 3 dust, 4 tip (ядрышко на конце щупа)
    unsigned int flags;    // 1 captured, 4 mine, 8 molCore, 16 held (ядро комка, прибито к концу щупа), 32 member (зерно комка)
    float ang;             // ядро: ориентация (рад). Тело на щупе: угол покоя относительно ориентации хоста
    float angVel;          // ядро: угловая скорость. Тело на щупе: длина покоя (расстояние до центра хоста)
    float tq;              // накопленный за подшаг «угловой момент» (сумма ошибок слотов)
    unsigned int nbr;      // соседей в радиусе INSTAB_R (инертоны)
    float heat;            // вспышка выброса/взрыва, 1 → 0
    float kAngle;          // ядро: жёсткость угла. Пыль в комке на щупе: номер щупа
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
    float rockForce;       // множитель силы между двумя свободными камнями: 1 — притяжение как у всех, <0 — отталкивание (проба «заряд»)
    float holdK;           // жёсткость щупа (связь хост — пойманный инертон)
    float holdLen;         // длина щупа: расстояние между центрами хоста и пойманного тела
    unsigned int holdOn;   // 1 = захват по щупам: хост упруго отбивает всё, что не на щупе
    float hostSpin;        // постоянное вращение хоста со щупами, рад/с (плюс = по часовой на экране)
    float holdDamp;        // демпфер щупа (вдоль и поперёк): гасит дёрганье пойманного тела
    float heldGravity;     // множитель гравитационной массы тела на щупе (1/3 = притягивает втрое слабее)
    float hostGravity;     // множитель гравитационной массы хоста при щупах (инерция прежняя)
    float memberPull;      // масса, с которой конец щупа притягивает зёрна СВОЕГО комка (держит их против вращения)
    float thermalKick;     // проба «тепло»: случайный толчок скорости за подшаг для тела массы 150 (0 — среда холодная)
    unsigned int seed;     // затравка случайных толчков, меняется каждый шаг
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
    simd_float2 cam;       // мировая позиция камеры (хост)
    float scale;           // точек на мировую единицу
    float worldSize;       // сторона тор-мира (фон тайлится с этим периодом)
    float viewRot;         // рад: поворот вида вокруг центра экрана (мир крутится под неподвижными кнопками)
} FrameUniforms;

#endif /* ShaderTypes_h */
