//
//  ShaderTypes.h
//  Fermentino
//
//  Структуры, общие для Swift и Metal. Только C-типы и simd.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

typedef struct {
    unsigned int bodyCount;
    float dt;                  // шаг подшага, с
    float radius;              // радиус тела, мировые единицы
    float gravity;             // G
    float softening;           // eps² для гравитации
    float damping;             // множитель скорости за подшаг
    float restitutionDamping;  // гашение скорости при расталкивании
    simd_float2 worldHalf;     // полуразмер мира (x, y)
    simd_uint2 gridDims;       // число ячеек по x и y
    float cellSize;            // размер ячейки (= 2 * radius)
    unsigned int cellCapacity; // максимум тел на ячейку
    simd_float2 attractor;     // позиция пальца, мировые координаты
    float attractorStrength;   // 0 = выключен
    float aspect;              // width / height экрана
} SimParams;

#endif /* ShaderTypes_h */
