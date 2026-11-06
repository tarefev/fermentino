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
    var firstDelay: Float = 0  // с до первого прилёта (дать прочитать стартовую реплику)
}

/// Пыль: много мелких тел случайного размера, живут по тем же законам, но не инертоны.
struct DustDef {
    var n: Int
    var rMin: Float
    var rMax: Float
    var density: Float      // масса = density·r²
    var minHostDist: Float = 0   // не рождать ближе к хосту
    var avoidZone = false        // не рождать в поглотителе
    var explode: ExplodeDef? = nil   // нестабильность плотного кома пыли (как у инертонов)
    var splitAbove: Int? = nil       // сцепленный комок больше стольких зёрен делится пополам
    var splitSpeed: Float = 120      // скорость, с которой половины расходятся (каждая от центра)
    var splitBoost: Float = 1.4      // во сколько раз скорость разлёта половин выше их скорости убегания друг от друга
    var splitLink: Float = 1.15      // зёрна в одном комке, если расстояние ≤ (rA + rB)·это
}

/// Щупы хоста: захват по валентности. Свободный щуп защёлкивает инертон на фиксированном расстоянии,
/// занятые — хост упруго отбивает. Швырять можно только то, что на щупе.
struct ProbeDef {
    var k: Float = 4000             // жёсткость щупа вдоль длины: масса вокруг не прижимает комок к кораблю
    var length: Float = 30          // длина щупа: от центра хоста до центра пойманного тела, мировые единицы
    var breakStretch: Float = 3     // срыв при растяжении > length·это
    var throwSpeed: Float = 400     // скорость вылета — одна при любом числе зёрен; отдача = суммарная масса × эта скорость
    var tipR: Float = 2.6           // радиус ядрышка на конце щупа
    var tipMass: Float = 150        // его инертная масса (притягивает щуп отдельно, см. probeMass)
    var maxClump = 12               // комок на щупе растёт до стольких зёрен, потом закрыт: к нему ничего не липнет
    var linkGap: Float = 1.08       // зерно цепляется к комку только касанием: расстояние ≤ (rA + rB)·это
    var dropR: Float = 18           // зерно комка, отнесённое дальше этого от конца щупа, отваливается
    var reload: Float = 2.8         // с после выстрела: ядрышко нарастает заново, щуп пока ничего не ловит и не стреляет
    var holdTime: Float = 0.45      // с удержания кнопки, чтобы выключить / включить щуп
    var colorByDirection = false    // ПРОБА: цвет и кнопка привязаны к направлению на экране, а не к щупу; «выключено» = направление не стреляет
    var arrowBase: Float = 0        // рад: куда стреляет кнопка 0 (на экране: 0 — вправо, +π/2 — вниз)
    var arrowStep: Float = 0        // рад: на сколько поворачивается стрелка от кнопки к кнопке (со знаком)
    var colorOffset = 0             // с какого оттенка палитры начинаются щупальца и их кнопки (2 — средний, коралловый)
    var mirrorRow = false           // зеркалить ряд кнопок, когда средняя смотрит вверх (пока выключено: автор думает над раскладкой)
    var sectorTilt: Float = 0       // рад: на сколько повёрнуты границы секторов (где щуп меняет цвет и кнопку) относительно стрелок; минус — против часовой
    var startOn: [Int]? = nil       // какие щупы включены на старте тура (nil = все); остальные выключены, игрок включает их сам
    var holdDelay: Float = 0.15     // с от касания до начала анимации удержания: обычный тап её не запускает
    var heldGravity: Float = 1.0 / 3.0   // тело на щупе притягивает втрое слабее
    var hostGravity: Float = 0.03   // корабль почти не притягивает (как тело массы 150): к борту ничего не стекается…
    var probeMass: Float = 1600     // …зато конец каждого свободного щупа притягивает как тело этой массы
    var fillingGravity: Float = 1.0 // пока комок на щупе растёт, вес щупа не падает; полный комок чужую пыль не притягивает
    var memberPull: Float = 1600    // конец щупа держит зёрна своего комка притяжением этой массы (хватает против вращения)
    var kAngle: Float = 40000       // жёсткость угла щупа: щупы не гнутся, держат свои углы против любой толпы
    var spin: Float = 2.8           // вращение щупов по часовой, рад/с игрового времени (оборот ~4.5 с)
    var damp: Float = 45            // демпфер щупа, около критического для его жёсткостей: без дёрганья
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
    var dust: DustDef? = nil        // пыль по миру
    var ejectSpeed: Float? = nil    // скорость выброса в туре (nil = K.EJECT_SPEED); отдача ∝ ей
    var probes: ProbeDef? = nil     // захват по щупам вместо «своих по близости»
    var maxSpeed: Float? = nil      // потолок скорости в туре (nil = K.MAX_SPEED)
    var substeps: Int? = nil        // подшагов физики на кадр (nil = K.SUBSTEPS); меньше — дешевле для телефона

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
                // пять щупалец по лучам звезды: пять одинаковых ядрышек уравновешивают друг друга, корабль не болтает
                "host": ElementDef(name: "Тесей", symbol: "Ts", color: rgb("#cc1414"), r: 8, mass: 5000, angles: [-90, -18, 54, 126, 198], kAngle: 300, control: "player", emblem: "ussr"),
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
            spawner: nil,                   // инертонов нет: ловим комки пыли
            zoneDistance: 1200,
            viscosity: 0.15,                // базовая: ниже — орбиты дольше, но захват заметно позже (нужен поток снарядов)
            dust: DustDef(n: 600, rMin: 1.95, rMax: 1.95, density: 40, minHostDist: 90, avoidZone: true,
                          splitAbove: 24),          // масса зерна ~150; комок больше 24 зёрен делится пополам
            ejectSpeed: 3300,               // отдача в 2.2 раза сильнее базовой: кораблём иначе не управлять
            // кнопка стреляет своим щупальцем туда, где оно сейчас. На старте включено одно, среднее; остальные
            // четыре выключены, игрок может включить их долгим нажатием, если догадается.
            // Управление по направлению (пять щупалец, стрелки, шкала с поворотом вида) было настроено так:
            // colorByDirection: true, arrowBase: 234°, arrowStep: −72°, sectorTilt: −14° — вернётся комплектующими.
            // ядрышко втрое тяжелее зерна (150 → 450): одиночный выстрел пустым щупальцем даёт заметный толчок.
            // Это настройка только первого тура — в следующих вес ядрышка задаётся заново.
            probes: ProbeDef(tipMass: 450, startOn: [2]),
            substeps: 3                     // 600 зёрен: три подшага устойчивы и на 40% дешевле пяти
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
