//
//  Rounds.swift
//  Fermentino
//
//  Раунды из dev-версии прототипа: каждый самодостаточен (элементы, связи, спавн, победа).
//

import simd

struct ExplodeDef {
    var max: Int
    var r: Float
    var speed: Float
    var burst: Int
    var rate: Float
    var rateRef: Float
}

struct ElementDef {
    var name: String
    var symbol: String
    var color: SIMD4<Float>
    var r: Float = 0
    var mass: Float = 0
    var angles: [Float]? = nil      // углы слотов (°) — геометрия молекулы
    var valence: Int? = nil         // либо просто число слотов, равномерно
    var kAngle: Float? = nil        // жёсткость угла этого ядра
    var control: String? = nil      // "player" — хост
    var emblem: String? = nil
    var ballast = false             // nitron: инертоны
    var density: Float = 0
    var groups: [(r: Float, n: Int)] = []
    var explode: ExplodeDef? = nil

    /// Слоты валентности в радианах: явные углы либо равномерно из valence.
    var slots: [Float] {
        if let a = angles { return a.map { $0 * .pi / 180 } }
        let v = valence ?? 0
        return (0..<v).map { Float($0) * 2 * .pi / Float(max(1, v)) }
    }
}

struct InteractionDef {
    var a: String
    var b: String
    var k: Float = 400
    var len: Float = 4
    var breakStretch: Float = 1.2
    var breakVel: Float = 600
}

enum WinKind: String {
    case star
    case benzene
    case reachZone      // хост долетел до поглотителя
}

/// Приток инертонов с края экрана в сторону хоста (обучающие туры).
struct SpawnerDef {
    var interval: Float     // с между прилётами
    var distance: Float     // откуда вылетает: расстояние от хоста
    var radialSpeed: Float  // скорость к хосту, ед/с
    var tangentSpeed: Float // боковая скорость, ед/с → выход на спираль вокруг хоста (знак случайный)
    var r: Float            // радиус инертона
    var startOnBoard = 0    // сколько инертонов уже на борту в начале тура
}

/// Какие рычаги и строки HUD включены в туре.
struct RoundControls {
    var hud = true          // служебные тексты вообще (HUD сверху, подсказка снизу)
    var valence = true      // A/S
    var mass = true         // E/R
    var gravity = true      // Q/W
    var toggles = true      // L/D/B
    var molecule = true     // связей / сцеплений / фермент
}

struct RoundDef {
    var id: String
    var win: WinKind
    var spawn: [(id: String, n: Int)]
    var elements: [String: ElementDef]
    var interactions: [InteractionDef]
    var intro: [String] = ["intro.molecule.1", "intro.molecule.2"]   // ключи Strings
    var introIcon = true            // рисовать целевую молекулу в интро
    var winSub = "win.molecule"     // ключ Strings
    var narration = false           // реплики диспетчерской по событиям (обучение)
    var controls = RoundControls()
    var spawner: SpawnerDef? = nil  // приток инертонов вместо разбросанных по карте
    var zoneDistance: Float? = nil  // поглотитель на этом расстоянии от старта (nil = случайно по карте)
    var viscosity: Float? = nil     // вязкость среды в туре (nil = K.VISCOSITY)

    /// Индекс пар "a-b" (по алфавиту) → параметры связи.
    func interactIndex() -> [String: InteractionDef] {
        var idx: [String: InteractionDef] = [:]
        for it in interactions {
            idx[RoundDef.pairKey(it.a, it.b)] = it
        }
        return idx
    }

    static func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)-\(b)" : "\(b)-\(a)"
    }
}

enum Rounds {
    static let INTERACT_DEFAULT = InteractionDef(a: "", b: "", k: 400, len: 4, breakStretch: 1.2, breakVel: 600)

    /// Порядок туров: 0 = полёт (обучение), 1 = звезда (хаб + 3 кэпа), 2 = бензол (кольцо 6 хабов + 6 кэпов)
    static let all: [RoundDef] = [
        RoundDef(
            id: "flight", win: .reachZone,
            spawn: [],
            elements: [
                "host": ElementDef(name: "Тесей", symbol: "Ts", color: rgb("#cc1414"), r: 8, mass: 5000, valence: 0, kAngle: 300, control: "player", emblem: "ussr"),
                "nitron": ElementDef(name: "nitron", symbol: "Ni", color: rgb("#8aa0bd"), valence: 0, ballast: true, density: 15,
                                     groups: [],
                                     explode: ExplodeDef(max: 32, r: 35, speed: 4000, burst: 8, rate: 2, rateRef: 16)),
            ],
            interactions: [],
            intro: [],
            introIcon: false,
            winSub: "win.flight",
            narration: true,
            controls: RoundControls(hud: false, valence: false, mass: false, gravity: false, toggles: false, molecule: false),
            spawner: SpawnerDef(interval: 1.5, distance: 450, radialSpeed: 120, tangentSpeed: 40, r: 6, startOnBoard: 0),   // при вязкости 0.15: в кольцо через ~9 с, ~2 оборота, касание через ~20 с
            zoneDistance: 1200,
            viscosity: 0.15                 // базовая: ниже — орбиты дольше, но захват заметно позже (нужен поток снарядов)
        ),
        RoundDef(
            id: "star", win: .star,
            spawn: [("trigen", 2), ("capsor", 5)],
            elements: [
                "host": ElementDef(name: "Тесей", symbol: "Ts", color: rgb("#cc1414"), r: 8, mass: 5000, valence: 3, kAngle: 300, control: "player", emblem: "ussr"),
                "trigen": ElementDef(name: "trigen", symbol: "Tg", color: rgb("#ff2db0"), r: 10, mass: 2800, angles: [0, 120, 240], kAngle: 2000),
                "capsor": ElementDef(name: "capsor", symbol: "Cp", color: rgb("#16f0e6"), r: 7, mass: 1120, angles: [0]),
                "nitron": ElementDef(name: "nitron", symbol: "Ni", color: rgb("#8aa0bd"), valence: 0, ballast: true, density: 15,
                                     groups: [(4, 270), (9, 20), (10, 10)],
                                     explode: ExplodeDef(max: 32, r: 35, speed: 4000, burst: 8, rate: 2, rateRef: 16)),
            ],
            interactions: [
                InteractionDef(a: "trigen", b: "host", k: 100, len: 4, breakStretch: 4, breakVel: 800),
                InteractionDef(a: "trigen", b: "trigen", k: 150, len: 4, breakStretch: 1.1, breakVel: 200),
                InteractionDef(a: "capsor", b: "trigen", k: 500, len: 3, breakStretch: 5, breakVel: 900),
                InteractionDef(a: "capsor", b: "host", k: 50, len: 4, breakStretch: 2.7, breakVel: 400),
                InteractionDef(a: "capsor", b: "capsor", k: 150, len: 5, breakStretch: 1.1, breakVel: 300),
            ]
        ),
        RoundDef(
            id: "benzene", win: .benzene,
            spawn: [("trigen", 10), ("capsor", 10)],
            elements: [
                "host": ElementDef(name: "Тесей", symbol: "Ts", color: rgb("#cc1414"), r: 8, mass: 5000, valence: 3, kAngle: 300, control: "player", emblem: "ussr"),
                "trigen": ElementDef(name: "trigen", symbol: "Tg", color: rgb("#ff2db0"), r: 10, mass: 1000, angles: [0, 120, 240], kAngle: 4000),
                "capsor": ElementDef(name: "capsor", symbol: "Cp", color: rgb("#16f0e6"), r: 7, mass: 500, angles: [0]),
                "nitron": ElementDef(name: "nitron", symbol: "Ni", color: rgb("#8aa0bd"), valence: 0, ballast: true, density: 2000,
                                     groups: [(2, 270), (3, 20), (4, 10)],
                                     explode: ExplodeDef(max: 100, r: 35, speed: 4000, burst: 6, rate: 4, rateRef: 16)),
            ],
            interactions: [
                InteractionDef(a: "trigen", b: "host", k: 100, len: 4, breakStretch: 1.2, breakVel: 600),
                InteractionDef(a: "trigen", b: "trigen", k: 300, len: 3, breakStretch: 3, breakVel: 900),
                InteractionDef(a: "capsor", b: "trigen", k: 100, len: 1.3, breakStretch: 5, breakVel: 1200),
                InteractionDef(a: "capsor", b: "host", k: 50, len: 4, breakStretch: 5, breakVel: 3000),
                InteractionDef(a: "capsor", b: "capsor", k: 150, len: 5, breakStretch: 1.3, breakVel: 300),
            ]
        ),
    ]
}
