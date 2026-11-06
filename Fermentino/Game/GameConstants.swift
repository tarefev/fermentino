//
//  GameConstants.swift
//  Fermentino
//
//  Константы K из веб-прототипа, один в один (имена сохранены для сверки).
//

import simd

enum K {
    // ---- Мир (§8, §9)
    static let WORLD_W: Float = 3600
    static let WORLD_H: Float = 3600
    static let N_ANCHORS = 0
    static let START_SPEED: Float = 6
    static let N_STARS = 520

    // ---- Массы / радиусы (§1)
    static let M_CORE: Float = 2800
    static let N_CAP = 3            // кэпов в рецепте звезды — для HUD
    static let K_ANGLE: Float = 500
    static let K_ANGLE_TORQUE: Float = 300
    static let ANG_DAMP: Float = 10
    static let R_CORE: Float = 8
    static let ANCHOR_MASS_MIN: Float = 8000
    static let ANCHOR_MASS_MAX: Float = 26000
    static let ANCHOR_R_MIN: Float = 34
    static let ANCHOR_R_MAX: Float = 64

    // ---- Гравитация (§2.1)
    static let G: Float = 200
    static let EPS2: Float = 120
    static let CUT_START: Float = 1500
    static let CUT_END: Float = 1700

    // ---- Отталкивание (§2.2)
    static let K_REP: Float = 20000
    static let V_STICK: Float = 1000
    static let STICK_MIN: Float = 0.03
    static let BOND_DAMP: Float = 5

    // ---- Управление / выброс (§4)
    static let EJECT_SPEED: Float = 1500
    static let EJECT_REF_MASS: Float = 240
    static let ENERGY_PULSE_FRAC: Float = 0.02
    static let ENERGY_PER_YELLOW: Float = 1
    static let EJECT_FADE: Float = 0.35
    static let GRAV_OFF_R_MULT: Float = 12
    static let PULSE_PERIOD: Float = 1.0
    static let MASS_STEP: Float = 30
    static let MASS_MAX: Float = 10000
    static let MASS_MIN: Float = 1

    // ---- «Своё тело» (§5, §7)
    static let LINK_R: Float = 60
    static let LINK_R_ATOM: Float = 22

    // ---- Интегрирование (§3)
    static let DT: Float = 1.0 / 60.0
    static let VIEW_ZOOM: Float = 1.2            // зум поля: 1 — как было, 1.2 — всё на 20% крупнее (проба 06.11)
    static let TIME_SCALE: Float = 0.5
    static let SUBSTEPS = 5
    static let MAX_SPEED: Float = 4000
    static let VISCOSITY: Float = 0.15

    // ---- Рендер (§6, §10)
    static let COL_BG = rgb("#05060a")
    static let COL_STAR = rgb("#243049")
    static let COL_STAR_BRIGHT = rgb("#3a4d74")
    static let COL_ATOM = rgb("#8aa0bd")
    static let COL_MINE = rgb("#3a9bff")
    // корабль: в начале тура ржавый и тёмный, потом «включается» — светлеет и начинает светиться
    // (было: красный корпус #cc1414 и золотая звезда #ffd60a — выходил флаг Вьетнама)
    static let COL_HULL = rgb("#6a3a24")          // ржавое железо; швы, заклёпки и разводы рисует шейдер (фигура 6)
    static let COL_HULL_ON = rgb("#efe6d6")       // включён: белая эмаль (вариант 1 с листа docs/ship-colors.png)
    static let COL_EMBLEM = rgb("#d81a1a")        // звезда
    static let COL_RIVET = COL_EMBLEM             // нашлёпки на борту — красные, как звезда
    static let SHIP_ON_DELAY: Float = 1.2         // сколько секунд корабль стоит ржавым
    static let SHIP_ON_TIME: Float = 3.5          // за сколько секунд разгорается
    static let TAGLINE_HOLD: Double = 2.0         // сколько секунд девиз висит целиком, прежде чем сам начнёт растворяться
    static let ARROW_LINE_PAUSE: Float = 1.0      // пауза между погасшей репликой про включение и репликой про стрелку
    static let ARROW_LINE_SHOW: Float = 4.8       // сколько секунд висит реплика про стрелку
    static let NEWTON_LINE_PAUSE: Float = 0.8     // пауза после неё перед репликой про Ньютона
    static let NEWTON_LINE_TAIL: Float = 1.5      // реплика про Ньютона висит до первого броска и уходит через столько секунд после него
    static let ROCKS_LINE_AFTER: Float = 5.0      // через сколько секунд после первого броска звучит реплика про камни
    static let SHIP_FADE_DELAY: Float = 1.0       // втянутый корабль висит в поглотителе столько секунд, прежде чем таять
    static let SHIP_FADE_TIME: Float = 0.9        // и тает за столько секунд
    static let CHALK_DELAY: Float = 0.7           // через сколько секунд после реплики про стрелку её обводят «мелом»
    static let PROLOGUE_FADE: Double = 2.0        // за сколько секунд девиз растворяется, открывая игру
    static let POWER_LINE_LEAD: Float = 0.4       // реплика про включение появляется за столько секунд до начала разгорания
    static let POWER_LINE_TAIL: Float = 1.1       // и гаснет через столько секунд после того, как корабль разгорелся
    static let COL_ANCHOR = rgb("#7a6a5c")
    static let COL_ANCHOR_EDGE = rgb("#b8a48f")
    static let RGB_HOT = SIMD4<Float>(235 / 255, 80 / 255, 60 / 255, 1)
    // щупы хоста: пять оттенков красного от светлого к тёмному; кнопка того же оттенка, что её щуп
    static let PROBE_COLORS: [SIMD4<Float>] = [rgb("#ffe0d6"), rgb("#ffab99"), rgb("#f8705e"), rgb("#d43b3b"), rgb("#9c2440")]

    // Чёрная дыра поглотителя
    static let BH_MAX: Float = 1e8
    static let BH_RAMP: Float = 20   // секунд от нуля до BH_MAX (рост массы медленный)
    static let DEBUG_WIN_TEST = false
}

func rgb(_ hex: String) -> SIMD4<Float> {
    let s = hex.dropFirst()
    guard s.count == 6, let n = UInt32(s, radix: 16) else { return SIMD4<Float>(1, 0, 1, 1) }
    return SIMD4<Float>(Float((n >> 16) & 255) / 255, Float((n >> 8) & 255) / 255, Float(n & 255) / 255, 1)
}

func rgba(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> SIMD4<Float> {
    SIMD4<Float>(r / 255, g / 255, b / 255, a)
}

func mixCol(_ base: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    var c = base + (K.RGB_HOT - base) * t
    c.w = 1
    return c
}
