//
//  GameConstants.swift
//  Fermentino
//
//  Константы K из веб-прототипа, один в один (имена сохранены для сверки).
//

import simd

struct BondParam {
    var k: Float
    var len: Float
}

enum CoreKind: String, Comparable {
    case red, hub, cap, yellow, new

    // JS сравнивает kind как строки: cap < hub < new < red < yellow
    static func < (lhs: CoreKind, rhs: CoreKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct CoreTemplate {
    var col: SIMD4<Float>
    var r: Float
    var m: Float
}

enum K {
    // ---- Мир (§8, §9)
    static let WORLD_W: Float = 3600
    static let WORLD_H: Float = 3600
    static let N_ANCHORS = 0
    static let START_SPEED: Float = 6
    static let N_STARS = 520

    // ---- Массы / радиусы (§1)
    static let M_CORE: Float = 2800
    static let N_CAP = 3
    static let N_YELLOW = 0
    static let N_NEW = 0
    static let VALENCE_ANGLES: [CoreKind: [Float]] = [
        .red: [0, 120, 240],
        .hub: [0, 120, 240],
        .cap: [0],
        .yellow: [0, 180],
        .new: [0, 120, 240],
    ]
    static let K_ANGLE: Float = 500
    static let K_ANGLE_TORQUE: Float = 300
    static let ANG_DAMP: Float = 10
    static let NEW_MASS_MULT: Float = 1.5
    static let ATOM_DENSITY: Float = 15
    static let ATOM_GROUPS: [(r: Float, n: Int)] = [(4, 270), (9, 20), (10, 10)]
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
    static let BOND_PARAMS: [String: BondParam] = [
        "hub-red": BondParam(k: 600, len: 4),
        "hub-hub": BondParam(k: 150, len: 4),
        "cap-hub": BondParam(k: 300, len: 3),
        "cap-red": BondParam(k: 250, len: 4),
        "cap-cap": BondParam(k: 100, len: 5),
        "red-yellow": BondParam(k: 250, len: 5),
        "new-red": BondParam(k: 125, len: 5),
        "new-yellow": BondParam(k: 150, len: 6),
        "yellow-yellow": BondParam(k: 50, len: 6),
        "new-new": BondParam(k: 150, len: 8),
    ]
    static let BOND_DEFAULT = BondParam(k: 400, len: 4)
    static let BOND_DAMP: Float = 5
    static let BOND_BREAK_MULT: Float = 1.2
    static let BOND_BREAK_VEL: Float = 600

    // ---- Управление / выброс (§4)
    static let EJECT_SPEED: Float = 1500
    static let EJECT_REF_MASS: Float = 240
    static let ENERGY_PULSE_FRAC: Float = 0.02
    static let ENERGY_PER_YELLOW: Float = 1
    static let INSTAB_MAX = 32
    static let INSTAB_R: Float = 35
    static let INSTAB_SPEED: Float = 4000
    static let INSTAB_BURST = 8
    static let INSTAB_RATE: Float = 2
    static let INSTAB_RATE_REF: Float = 16
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
    static let COL_CORE = rgb("#ffd24a")
    static let COL_CORE_MAIN = rgb("#ff6a3a")
    static let COL_NEW = rgb("#9a6cff")
    static let COL_CAP = rgb("#16f0e6")
    static let COL_HUB = rgb("#ff2db0")
    static let COL_ANCHOR = rgb("#7a6a5c")
    static let COL_ANCHOR_EDGE = rgb("#b8a48f")
    static let RGB_HOT = SIMD4<Float>(235 / 255, 80 / 255, 60 / 255, 1)

    // Шаблоны ядер (KIND в setup)
    static let CORE_KINDS: [CoreKind: CoreTemplate] = [
        .red: CoreTemplate(col: COL_CORE_MAIN, r: R_CORE, m: 5000),
        .yellow: CoreTemplate(col: COL_CORE, r: R_CORE, m: M_CORE),
        .new: CoreTemplate(col: COL_NEW, r: R_CORE - 1, m: M_CORE * NEW_MASS_MULT),
        .cap: CoreTemplate(col: COL_CAP, r: R_CORE - 1, m: M_CORE * 0.4),
        .hub: CoreTemplate(col: COL_HUB, r: R_CORE + 2, m: M_CORE),
    ]

    // Чёрная дыра поглотителя
    static let BH_MAX: Float = 1e8
    static let BH_RAMP: Float = 2
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
