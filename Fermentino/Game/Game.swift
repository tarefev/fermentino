//
//  Game.swift
//  Fermentino
//
//  Перенос игровой логики веб-прототипа (dev-версия) один в один: тела живут в общем буфере
//  GPU, вся логика раунда (связи, выброс, «свои», нестабильность, победа) — здесь, на CPU.
//

import Foundation
import UIKit
import QuartzCore
import simd

struct CoreInfo {
    var kind: String              // id элемента: host / trigen / capsor / …
    var main: Bool
    var col: SIMD4<Float>
    var spinPhase: Float
    var slots: [Float]            // углы слотов (рад); валентность = slots.count
    var kAngle: Float
    var emblem: String? = nil
    var bonds: [Int: Int] = [:]   // партнёр (индекс ядра) → индекс слота

    var valence: Int { slots.count }
}

struct Zone {
    var x: Float
    var y: Float
    var r: Float
    var m: Float
    var bhT: Float = 0
}

struct Puff {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var life: Float
}

/// Волны от выстрела: из точки борта к щупальцу slot расходятся концентрические дуги. Передняя дуга доходит
/// до ядрышка за delay — в этот момент комок и срывается; дуги идут дальше сквозь него и гаснут.
struct ShotWave {
    var slot: Int
    var strength: Float
    var out: SIMD2<Float>        // направление на щупальце (мировое); до выстрела следит за щупальцем
    var t: Float                 // секунд с нажатия
    var fired = false
    var weak = false             // холостая: щупальце ещё восстанавливается — волна показывает намерение, но не достаёт
    static let delay: Float = 0.13      // за сколько передняя дуга доходит до ядрышка
    static let lag: Float = 0.045       // на сколько отстают вторая и третья дуги
    static let overshoot: Float = 1.8   // докуда дуги идут дальше ядрышка (в расстояниях борт — ядрышко)
    static let spread: Float = 0.62     // полуширина волны на единицу пройденного пути (конус около ±38°)
    static let fullUntil: Float = 1.15  // до этого расстояния (в расстояниях борт — ядрышко) волна толкает в полную силу
    static let weakReach: Float = 0.72  // докуда доходит холостая волна (в расстояниях борт — ядрышко): заметно, но не достаёт
    static let weakPower: Float = 0.1   // во сколько раз холостая волна толкает слабее настоящей
    var life: Float { (weak ? ShotWave.delay * ShotWave.weakReach : ShotWave.delay * ShotWave.overshoot) + 2 * ShotWave.lag }
}

struct Star {
    var x: Float
    var y: Float
    var big: Bool
}

struct EjectRequest {
    var point: Bool
    var x: Float
    var y: Float
}

enum EjectMode: String {
    case intoCore
    case opposite
}

enum HudKey {
    case massUp, massDown, gravRight, gravLeft, valenceDown, valenceUp
    case toggleDebug, toggleEjectMode, toggleBonds, restart, nextRound
}

final class Game {
    static let HALF_W = K.WORLD_W / 2
    static let HALF_H = K.WORLD_H / 2

    let sim: GPUSimulation
    let hud: HUDModel
    var bodies: UnsafeMutablePointer<Body> { sim.bodies }

    // ---- раунд
    private(set) var round: RoundDef = Rounds.all[Progress.roundIndex]
    private var spawnTimer: Float = 0

    // ---- щупы хоста (захват по валентности)
    private(set) var held: [[Int]] = []      // слот хоста → индексы зёрен комка на этом щупе (пусто = свободен)
    private(set) var nuclei: [Int] = []      // слот хоста → индекс ядрышка на конце щупа (постоянное тело)
    private var bullets: [Int] = []          // выстреленные копии ядрышек; старые переиспользуются, чтобы тел не становилось всё больше
    private var holdOrder: [Int] = []        // слоты в порядке захвата, последний — самый свежий
    private(set) var probePulse: [Float] = [] // 1→0: пустой щуп дёргается, когда нажали его кнопку
    private(set) var probeReload: [Float] = [] // с до конца перезарядки щупа после выстрела (0 = готов)
    private(set) var probeOff: [Bool] = []     // щуп выключен: ничего не ловит
    private var probePress: [Float] = []       // с, сколько держат кнопку щупа; -1 = не нажата; .infinity = уже сработало
    /// 0…1: насколько дожато долгое нажатие на кнопку щупа s (для анимации на кнопке и на щупе).
    func probeHoldProgress(_ s: Int) -> Float {
        guard let pr = round.probes, s < probePress.count else { return 0 }
        let t = probePress[s]
        if t < pr.holdDelay || t == .infinity { return 0 }
        return min(1, (t - pr.holdDelay) / max(0.01, pr.holdTime - pr.holdDelay))
    }
    var probesOn: Bool { round.probes != nil }

    // ---- ПРОБА: цвет и кнопка по направлению. У каждой кнопки своя стрелка — направление на экране;
    // стрелки стоят через равный угол (как лучи пятиугольника). «Сектор» щупа — кнопка, чья стрелка сейчас
    // ближе всего к нему. В этом режиме probeOff и нажатия кнопок считаются по секторам, а ловят все щупы.
    var byDirection: Bool { round.probes?.colorByDirection ?? false }
    /// Положение шкалы над кнопками (рад). Шкала крутит не стрелки, а сам вид: кнопки и их стрелки стоят
    /// на месте, мир поворачивается под ними. Живёт, пока запущено приложение, перезапуск тура его не сбрасывает.
    static var starTurn: Float = 0
    /// Поворот вида вокруг корабля (рад, по часовой на экране). Тянешь шкалу вправо — мир идёт за пальцем,
    /// то есть против часовой.
    var viewRot: Float { byDirection ? -Game.starTurn : 0 }
    /// Угол стрелки кнопки k на экране (рад; 0 — вправо, +π/2 — вниз).
    func arrowAngle(_ k: Int) -> Float {
        guard let pr = round.probes else { return 0 }
        return middleAngle + effStep * Float(k - cores[0].slots.count / 2)
    }
    /// Куда смотрит средняя кнопка (главная метка на корабле): исходное направление плюс поворот шкалой.
    private var middleAngle: Float {
        guard let pr = round.probes else { return 0 }
        return pr.arrowBase + pr.arrowStep * Float(cores[0].slots.count / 2)
    }
    /// Шаг между стрелками соседних кнопок. Ряд кнопок — это круг, развёрнутый в линию; чтобы левые кнопки
    /// всегда кидали влево, а правые вправо, порядок по кругу зеркалится, когда средняя кнопка смотрит вверх.
    private var effStep: Float {
        guard let pr = round.probes else { return 0 }
        return starMirrored ? -pr.arrowStep : pr.arrowStep
    }
    private(set) var starMirrored = false
    private var arrowShown: [Float] = []       // углы стрелок для кнопок, развёрнутые без скачков через 360°
    /// Раз в кадр: зеркалим ряд, когда средняя кнопка переходит через горизонталь (с запасом 3°, чтобы
    /// у самой горизонтали раскладка не дёргалась туда-сюда).
    private func updateStarMirror() {
        guard byDirection, round.probes?.mirrorRow == true else { starMirrored = false; return }
        let up = -sin(middleAngle)                  // > 0 — средняя кнопка смотрит в верхнюю половину
        let margin = sin(3 * Float.pi / 180)
        if !starMirrored && up > margin { starMirrored = true }
        if starMirrored && up < -margin { starMirrored = false }
    }
    /// Положение щупа s вдоль ряда кнопок: целое — ровно на стрелке кнопки, дробное — между соседними.
    private func sectorPos(_ s: Int) -> Float {
        guard let pr = round.probes, pr.arrowStep != 0 else { return Float(s) }
        return (bodies[0].ang + cores[0].slots[s] + viewRot - arrowAngle(0) - pr.sectorTilt) / effStep
    }
    /// Сектор (направление на экране, он же номер кнопки и цвета), в котором сейчас щуп s.
    func probeSector(_ s: Int) -> Int {
        let n = cores[0].slots.count
        if !byDirection || n == 0 { return s }
        return ((Int(sectorPos(s).rounded()) % n) + n) % n
    }
    /// Между какими двумя секторами щуп s и насколько он уже перешёл во второй: по этому его цвет
    /// плавно перетекает из одного оттенка в другой.
    func probeSectorBlend(_ s: Int) -> (from: Int, to: Int, t: Float) {
        let n = cores[0].slots.count
        if !byDirection || n == 0 { return (s, s, 0) }
        let pos = sectorPos(s), base = pos.rounded(.down)
        let a = ((Int(base) % n) + n) % n
        return (a, (a + 1) % n, pos - base)
    }
    /// Щуп, который сейчас в секторе k.
    func sectorProbe(_ k: Int) -> Int {
        let n = cores[0].slots.count
        if !byDirection { return k }
        for s in 0..<n where probeSector(s) == k { return s }
        return k
    }
    /// Щуп s ничего не ловит (в режиме «по направлению» ловят все).
    private func physOff(_ s: Int) -> Bool { byDirection ? false : probeOff[s] }
    var controlMode: ControlMode = .buttons

    // ---- реплики диспетчерской (обучение)
    private var narrationQueue: [(text: String, show: Float?)] = []
    private var narrationShow: Float?            // сколько секунд висит текущая реплика; nil — по длине текста
    /// Реплики, которые сейчас звучат. Остальные сняты до обсуждения: их места в коде и строки в таблице
    /// остались, чтобы вернуть реплику, достаточно добавить её ключ сюда.
    private static let activeLines: Set<String> = ["flight.power", "flight.arrow"]
    /// Обводка стрелки к поглотителю «мелом»: секунды с её начала, −1 — не идёт. Один раз за тур.
    private(set) var chalkT: Float = -1
    private var chalkDone = false
    static let chalkLife: Float = 2.3
    private var narrationShownAt: Float = -1
    private var said: Set<String> = []
    private var elements: [String: ElementDef] = [:]
    private var interactIndex: [String: InteractionDef] = [:]

    // ---- состояние раунда
    private(set) var count = 0
    private(set) var cores: [CoreInfo] = []
    private(set) var zone = Zone(x: 0, y: 0, r: 130, m: 0)
    var gravMode = 0               // -1 пульсар · 0 норма · 1 выкл
    var pulseTimer: Float = 0
    private(set) var body: [Int] = []
    private(set) var yellowCount = 0
    private(set) var gravBubbleOn = false
    var gfxSpin: Float = 0
    private(set) var won = false
    private(set) var winning = false
    private var winMol: [Int] = []
    private var winBannerT: Float = -1
    private(set) var introT: Float = 0
    /// Отсчёт тура придержан: пока игра проступает из-под девиза, introT стоит на нуле.
    var introHold = false
    /// «Включение» корабля в начале тура: 0 — ржавый и тёмный, 1 — разгорелся.
    var shipOn: Float {
        let t = (introT - K.SHIP_ON_DELAY) / K.SHIP_ON_TIME
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return t * t * (3 - 2 * t)
    }
    /// Корабль тает в поглотителе: 1 — виден целиком, 0 — исчез. Пока его втягивает, он уменьшается,
    /// а на последних 40% пути ещё и становится прозрачным.
    var shipFade: Float {
        let c = bodies[0].cap
        if c <= 0.6 { return 1 }
        return max(0, 1 - (c - 0.6) / 0.4)
    }
    /// Цвет корпуса корабля сейчас: от ржавого к светлому по мере включения.
    var hullColor: SIMD4<Float> {
        var c = K.COL_HULL + (K.COL_HULL_ON - K.COL_HULL) * shipOn
        c.w = 1
        return c
    }
    private(set) var assembled = false
    private(set) var roundT: Float = 0
    private(set) var puffs: [Puff] = []
    private(set) var shotWaves: [ShotWave] = []
    private(set) var stars: [Star] = []
    private var ejectQueue: [EjectRequest] = []
    var showDebug = false
    var showBonds = true
    var ejectMode: EjectMode = .opposite

    // ---- цикл
    private var last = CACurrentMediaTime()
    private var acc: Float = 0
    private(set) var fps: Float = 0
    private var fpsAcc: Float = 0
    private var fpsFrames = 0

    init(sim: GPUSimulation, hud: HUDModel) {
        self.sim = sim
        self.hud = hud
        setup()
    }

    // MARK: - Тор

    static func wrapDelta(_ d: Float, _ half: Float, _ full: Float) -> Float {
        if d > half { return d - full }
        if d < -half { return d + full }
        return d
    }

    static func wrapCoord(_ v: Float, _ full: Float) -> Float {
        var r = v.truncatingRemainder(dividingBy: full)
        if r < 0 { r += full }
        return r
    }

    @inline(__always) func dx(_ a: Float, _ b: Float) -> Float { Game.wrapDelta(a - b, Game.HALF_W, K.WORLD_W) }
    @inline(__always) func dy(_ a: Float, _ b: Float) -> Float { Game.wrapDelta(a - b, Game.HALF_H, K.WORLD_H) }

    var mainCore: Body { bodies[0] }

    // MARK: - Тело игрока и связи

    func computeBody() {
        let ar2 = (K.R_CORE * K.GRAV_OFF_R_MULT) * (K.R_CORE * K.GRAV_OFF_R_MULT)
        let r0 = bodies[0]
        body = [0]
        var inBody: Set<Int> = [0]
        for j in 1..<max(1, cores.count) {
            let ddx = dx(bodies[j].pos.x, r0.pos.x), ddy = dy(bodies[j].pos.y, r0.pos.y)
            if ddx * ddx + ddy * ddy <= ar2 { body.append(j); inBody.insert(j) }
        }
        var i = 0
        while i < body.count {
            for nb in cores[body[i]].bonds.keys where !inBody.contains(nb) {
                body.append(nb); inBody.insert(nb)
            }
            i += 1
        }
        yellowCount = body.count - 1
    }

    /// Параметры связи пары по видам ядер — из индекса взаимодействий раунда.
    func bondParams(_ a: String, _ b: String) -> InteractionDef {
        interactIndex[RoundDef.pairKey(a, b)] ?? Rounds.INTERACT_DEFAULT
    }

    func nearestFreeSlot(_ c: Int, dir: Float) -> Int {
        let used = Set(cores[c].bonds.values)
        var best = 0
        var bestErr = Float.infinity
        for k in 0..<cores[c].slots.count where !used.contains(k) {
            var e = dir - (bodies[c].ang + cores[c].slots[k])
            e = atan2(sin(e), cos(e))
            if abs(e) < bestErr { bestErr = abs(e); best = k }
        }
        return best
    }

    func setValence(_ c: Int, _ nvIn: Int) {
        let nv = max(0, min(12, nvIn))
        cores[c].slots = (0..<nv).map { Float($0) * 2 * .pi / Float(nv) }
        let partners = Array(cores[c].bonds.keys)
        cores[c].bonds = [:]
        for p in partners {
            if cores[c].bonds.count < nv {
                let ddx = dx(bodies[p].pos.x, bodies[c].pos.x), ddy = dy(bodies[p].pos.y, bodies[c].pos.y)
                cores[c].bonds[p] = nearestFreeSlot(c, dir: atan2(ddy, ddx))
            } else {
                cores[p].bonds.removeValue(forKey: c)
            }
        }
    }

    func updateBonds() {
        let n = cores.count
        for i in 0..<n {
            for j in (i + 1)..<max(i + 1, n) {
                if bodies[i].isCaptured || bodies[j].isCaptured { continue }
                let A = bodies[i], B = bodies[j]
                let ddx = dx(B.pos.x, A.pos.x), ddy = dy(B.pos.y, A.pos.y)
                let r = hypot(ddx, ddy)
                let bp = bondParams(cores[i].kind, cores[j].kind)
                let L = (A.r + B.r) * bp.len
                if cores[i].bonds[j] != nil {
                    let rr: Float = r == 0 ? 1 : r
                    let vn = ((A.vel.x - B.vel.x) * ddx + (A.vel.y - B.vel.y) * ddy) / rr
                    if r > L * max(bp.breakStretch, 1.15) || abs(vn) > bp.breakVel {
                        cores[i].bonds.removeValue(forKey: j)
                        cores[j].bonds.removeValue(forKey: i)
                    }
                } else if r <= L * 1.1 && cores[i].bonds.count < cores[i].valence && cores[j].bonds.count < cores[j].valence {
                    let phi = atan2(ddy, ddx)
                    cores[i].bonds[j] = nearestFreeSlot(i, dir: phi)
                    cores[j].bonds[i] = nearestFreeSlot(j, dir: phi + .pi)
                }
            }
        }
    }

    /// Матрицы связей и слотов → буферы GPU.
    private func syncBondsToGPU() {
        let mc = Int(FERM_MAX_CORES), ms = Int(FERM_MAX_SLOTS)
        // притяжение концов щупов: тянет только свободный и включённый щуп
        for s in 0..<ms {
            var pm: Float = 0
            if let pr = round.probes, s < held.count, !physOff(s) {
                if held[s].isEmpty { pm = pr.probeMass }
                else if held[s].count < pr.maxClump { pm = pr.probeMass * pr.fillingGravity }
            }
            sim.probeMass[s] = pm
        }
        // флаг «на щупе» для ядра сил (место покоя тело хранит само: ang и angVel)
        if probesOn {
            for o in 0..<count { bodies[o].flags &= ~BodyFlag.group }
            for (s, n) in nuclei.enumerated() {
                bodies[n].flags |= BodyFlag.held                 // ядрышко всегда прибито к концу своего щупа
                bodies[n].kAngle = Float(s)
            }
            for (s, clump) in held.enumerated() {
                for j in clump {
                    bodies[j].flags |= BodyFlag.member           // зерно комка: держится притяжением щупа и контактом
                    bodies[j].kAngle = Float(s)                  // номер щупа
                }
            }
        }
        for i in 0..<mc {
            for j in 0..<mc {
                let idx = i * mc + j
                guard i < cores.count, j < cores.count else { sim.bondSlot[idx] = -1; continue }
                if let slot = cores[i].bonds[j] { sim.bondSlot[idx] = Int32(slot) } else { sim.bondSlot[idx] = -1 }
                let bp = bondParams(cores[i].kind, cores[j].kind)
                sim.bondK[idx] = bp.k
                sim.bondLen[idx] = bp.len
            }
            for k in 0..<ms {
                var v: Float = 0
                if i < cores.count && k < cores[i].slots.count { v = cores[i].slots[k] }
                sim.slots[i * ms + k] = v
            }
        }
    }

    // MARK: - Старт

    private func rnd(_ a: Float, _ b: Float) -> Float {
        if b <= a { return a }          // пустой диапазон (например, разброс 0) → без случайности
        return Float.random(in: a..<b)
    }

    private func makeCore(_ kind: String, x: Float, y: Float, main: Bool) -> (Body, CoreInfo) {
        let e = elements[kind]!
        var b = Body()
        b.pos = SIMD2<Float>(x, y)
        b.type = BodyType.core
        b.r = e.r
        b.m = e.mass
        b.kAngle = e.kAngle ?? K.K_ANGLE
        let info = CoreInfo(kind: kind, main: main, col: e.color, spinPhase: rnd(0, .pi * 2), slots: e.slots,
                            kAngle: e.kAngle ?? K.K_ANGLE, emblem: e.emblem)
        return (b, info)
    }

    func setup() {
        round = Rounds.all[Progress.roundIndex]
        elements = round.elements
        interactIndex = round.interactIndex()
        spawnTimer = 0

        count = 0
        cores = []
        ejectQueue = []
        won = false; winning = false; winMol = []; winBannerT = -1; introT = 0; assembled = false; roundT = 0; puffs = []; shotWaves = []
        hud.showWin = false
        hud.winKind = round.win
        hud.introLines = round.intro.map { Strings.t($0) }
        hud.introIcon = round.introIcon
        hud.winSub = Strings.t(round.winSub)
        narrationQueue = []; narrationShownAt = -1; narrationShow = nil; said = []
        chalkT = -1; chalkDone = false
        hud.narration = ""; hud.narrationOpacity = 0
        hud.hasNext = Progress.hasNext
        hud.controls = round.controls
        zone = Zone(x: rnd(0, K.WORLD_W), y: rnd(0, K.WORLD_H), r: 130, m: 0)
        if let d = round.zoneDistance {
            // поглотитель на заданном расстоянии от старта хоста, направление случайное
            let a = rnd(0, .pi * 2)
            zone.x = Game.wrapCoord(Game.HALF_W + cos(a) * d, K.WORLD_W)
            zone.y = Game.wrapCoord(Game.HALF_H + sin(a) * d, K.WORLD_H)
        }

        var pending: [(Body, CoreInfo)] = []
        pending.append(makeCore("host", x: Game.HALF_W, y: Game.HALF_H, main: true))
        if K.DEBUG_WIN_TEST {
            // ТЕСТ ПОГЛОТИТЕЛЯ: хост + готовая молекула текущего раунда подальше от зоны
            let off: Float = 300
            let mx = Game.wrapCoord(zone.x + off, K.WORLD_W), my = zone.y
            let capL = (elements["trigen"]!.r + elements["capsor"]!.r) * bondParams("capsor", "trigen").len
            if round.win == .benzene {
                let Rhex = (elements["trigen"]!.r * 2) * bondParams("trigen", "trigen").len
                pending[0].0.pos = SIMD2<Float>(Game.wrapCoord(mx + Rhex + capL + 60, K.WORLD_W), my)
                var trig: [Int] = []
                for k in 0..<6 {
                    let th = Float(k) * .pi / 3
                    var t = makeCore("trigen", x: mx + cos(th) * Rhex, y: my + sin(th) * Rhex, main: false)
                    t.0.ang = th
                    var c = makeCore("capsor", x: mx + cos(th) * (Rhex + capL), y: my + sin(th) * (Rhex + capL), main: false)
                    c.0.ang = th + .pi
                    let ti = pending.count, ci = ti + 1
                    t.1.bonds[ci] = 0; c.1.bonds[ti] = 0
                    pending.append(t); pending.append(c)
                    trig.append(ti)
                }
                for k in 0..<6 {
                    let a = trig[k], b = trig[(k + 1) % 6]
                    pending[a].1.bonds[b] = 1
                    pending[b].1.bonds[a] = 2
                }
            } else {
                pending[0].0.pos = SIMD2<Float>(Game.wrapCoord(mx + capL + 40, K.WORLD_W), my)
                var hub = makeCore("trigen", x: mx, y: my, main: false)
                let hubIndex = pending.count
                var caps: [(Body, CoreInfo)] = []
                for k in 0..<3 {
                    let a = hub.1.slots[k]
                    var cap = makeCore("capsor", x: mx + cos(a) * capL, y: my + sin(a) * capL, main: false)
                    cap.0.ang = a + .pi
                    hub.1.bonds[hubIndex + 1 + k] = k
                    cap.1.bonds[hubIndex] = 0
                    caps.append(cap)
                }
                pending.append(hub)
                pending.append(contentsOf: caps)
            }
        } else {
            for (id, cnt) in round.spawn {
                for _ in 0..<cnt {
                    pending.append(makeCore(id, x: rnd(0, K.WORLD_W), y: rnd(0, K.WORLD_H), main: false))
                }
            }
        }

        for (b, info) in pending {
            bodies[count] = b
            cores.append(info)
            count += 1
        }
        held = []
        holdOrder = []
        nuclei = []
        bullets = []
        if let pr = round.probes {
            held = Array(repeating: [], count: cores[0].slots.count)
            // ядрышки на концах щупов: постоянные тела, часть корабля
            for sl in 0..<cores[0].slots.count {
                let a = bodies[0].ang + cores[0].slots[sl]
                var b = Body()
                b.type = BodyType.tip
                b.pos = bodies[0].pos + SIMD2<Float>(cos(a), sin(a)) * pr.length
                b.r = pr.tipR
                b.m = pr.tipMass
                b.ang = cores[0].slots[sl]          // место покоя: угол щупа…
                b.angVel = pr.length                // …и его длина
                b.kAngle = Float(sl)
                b.flags = BodyFlag.held
                nuclei.append(count)
                bodies[count] = b; count += 1
            }
            probePulse = Array(repeating: 0, count: cores[0].slots.count)
            probeReload = Array(repeating: 0, count: cores[0].slots.count)
            probeOff = Array(repeating: false, count: cores[0].slots.count)
            if let startOn = round.probes?.startOn {
                for s in 0..<probeOff.count where !startOn.contains(s) { probeOff[s] = true }
            }
            probePress = Array(repeating: -1, count: cores[0].slots.count)
            bodies[0].kAngle = pr.kAngle
        }

        for _ in 0..<K.N_ANCHORS {
            let m = rnd(K.ANCHOR_MASS_MIN, K.ANCHOR_MASS_MAX)
            let t = (m - K.ANCHOR_MASS_MIN) / (K.ANCHOR_MASS_MAX - K.ANCHOR_MASS_MIN)
            var b = Body()
            b.type = BodyType.anchor
            b.pos = SIMD2<Float>(rnd(0, K.WORLD_W), rnd(0, K.WORLD_H))
            b.m = m
            b.r = K.ANCHOR_R_MIN + t * (K.ANCHOR_R_MAX - K.ANCHOR_R_MIN)
            bodies[count] = b; count += 1
        }

        // Свободные атомы (nitron) — группы из элемента, случайно, низкие скорости
        let ni = elements["nitron"]!
        for g in ni.groups {
            for _ in 0..<g.n {
                guard count < sim.capacity else { break }
                var b = Body()
                b.type = BodyType.atom
                b.pos = SIMD2<Float>(rnd(0, K.WORLD_W), rnd(0, K.WORLD_H))
                b.vel = SIMD2<Float>(rnd(-K.START_SPEED, K.START_SPEED), rnd(-K.START_SPEED, K.START_SPEED))
                b.m = ni.density * g.r * g.r
                b.r = g.r
                bodies[count] = b; count += 1
            }
        }

        // пыль: мелкие тела случайного размера по всему миру, те же законы, но не инертоны
        if let d = round.dust {
            let host = bodies[0]
            for _ in 0..<d.n {
                guard count < sim.capacity else { break }
                var pos = SIMD2<Float>(rnd(0, K.WORLD_W), rnd(0, K.WORLD_H))
                var tries = 0
                while tries < 50 {
                    let dh = hypot(dx(pos.x, host.pos.x), dy(pos.y, host.pos.y))
                    let dz = hypot(dx(pos.x, zone.x), dy(pos.y, zone.y))
                    let okHost = dh >= d.minHostDist
                    let okZone = !d.avoidZone || dz > zone.r + 20
                    if okHost && okZone { break }
                    pos = SIMD2<Float>(rnd(0, K.WORLD_W), rnd(0, K.WORLD_H)); tries += 1
                }
                var b = Body()
                b.type = BodyType.dust
                b.pos = pos
                b.vel = SIMD2<Float>(rnd(-K.START_SPEED, K.START_SPEED), rnd(-K.START_SPEED, K.START_SPEED))
                b.r = rnd(d.rMin, d.rMax)
                b.m = d.density * b.r * b.r
                bodies[count] = b; count += 1
            }
        }

        // стартовый запас инертонов на борту (обучающие туры): кольцом вокруг хоста, с круговой скоростью
        if let sp = round.spawner, sp.startOnBoard > 0, let ni = elements["nitron"] {
            let host = bodies[0]
            let orbitR = host.r + sp.r + 10
            let vOrbit = sqrt(K.G * host.m / orbitR)
            for k in 0..<sp.startOnBoard {
                guard count < sim.capacity else { break }
                let a = Float(k) * 2 * .pi / Float(sp.startOnBoard)
                let dir = SIMD2<Float>(cos(a), sin(a))
                var b = Body()
                b.type = BodyType.atom
                b.pos = SIMD2<Float>(Game.wrapCoord(host.pos.x + dir.x * orbitR, K.WORLD_W),
                                     Game.wrapCoord(host.pos.y + dir.y * orbitR, K.WORLD_H))
                b.vel = SIMD2<Float>(-dir.y, dir.x) * vOrbit
                b.m = ni.density * sp.r * sp.r
                b.r = sp.r
                bodies[count] = b; count += 1
            }
        }

        stars = (0..<K.N_STARS).map { _ in Star(x: rnd(0, K.WORLD_W), y: rnd(0, K.WORLD_H), big: Float.random(in: 0..<1) < 0.18) }

        computeBody()
        updateMine()
    }

    // MARK: - Реплики по событиям

    /// Сказать реплику один раз за раунд (только в турах с нарративом).
    private func say(_ key: String, show: Float? = nil) {
        guard round.narration, Game.activeLines.contains(key), !said.contains(key) else { return }
        said.insert(key)
        narrationQueue.append((Strings.t(key), show))
    }

    private func advanceNarration() {
        // время показа по длине текста: ~14 знаков в секунду, не меньше 3 с; следующая реплика
        // не вытесняет текущую, пока та не дочитана
        let fade: Float = 1.0
        var minShow = max(3.0, Float(hud.narration.count) / 14.0)
        var maxShow = minShow + 2.5
        if let fixed = narrationShow { minShow = fixed; maxShow = fixed }     // реплика с заданным временем показа
        let shown = introT - narrationShownAt
        let hasCurrent = narrationShownAt >= 0 && shown < maxShow
        if !narrationQueue.isEmpty && (!hasCurrent || shown >= minShow) {
            let next = narrationQueue.removeFirst()
            hud.narration = next.text
            narrationShow = next.show
            narrationShownAt = introT
            hud.narrationOpacity = 1
            return
        }
        if !hasCurrent { if hud.narrationOpacity != 0 { hud.narrationOpacity = 0 }; return }
        var op: Double = 1
        if shown > maxShow - fade { op = Double((maxShow - shown) / fade) }
        if hud.narrationOpacity != op { hud.narrationOpacity = max(0, op) }
    }

    // MARK: - Выброс (§4)

    private func doEject(_ best: Int, _ dxn: Float, _ dyn: Float, strength: Float = 1) {
        bodies[best].heat = 1
        say("flight.moving")
        let ejectSpeed = (round.ejectSpeed ?? K.EJECT_SPEED) * strength
        let es = ejectSpeed * sqrt(1 + Float(yellowCount) * K.ENERGY_PER_YELLOW) * (K.EJECT_REF_MASS / bodies[best].m)
        if ejectMode == .intoCore {
            let ctr = mainCore
            let tx = dx(ctr.pos.x, bodies[best].pos.x), ty = dy(ctr.pos.y, bodies[best].pos.y)
            var tl = hypot(tx, ty); if tl == 0 { tl = 1 }
            bodies[best].vel += SIMD2<Float>(tx / tl * es, ty / tl * es)
        } else {
            bodies[best].vel += SIMD2<Float>(dxn * es, dyn * es)
            let P = bodies[best].m * es
            var w: [Float] = []
            var wsum: Float = 0
            for c in body {
                let ddx = dx(bodies[c].pos.x, bodies[best].pos.x), ddy = dy(bodies[c].pos.y, bodies[best].pos.y)
                let wi = 1 / (ddx * ddx + ddy * ddy + 400)
                w.append(wi); wsum += wi
            }
            for (i, c) in body.enumerated() {
                let imp = P * w[i] / wsum
                bodies[c].vel -= SIMD2<Float>(dxn * imp / bodies[c].m, dyn * imp / bodies[c].m)
            }
        }
    }

    private func energyPulse(_ dxIn: Float, _ dyIn: Float) {
        var len = hypot(dxIn, dyIn); if len == 0 { len = 1 }
        let dxn = dxIn / len, dyn = dyIn / len
        var M: Float = 0
        for c in body { M += bodies[c].m }
        if M > 0 {
            let P = K.EJECT_REF_MASS * K.EJECT_SPEED * K.ENERGY_PULSE_FRAC
            for c in body { bodies[c].vel -= SIMD2<Float>(dxn * P / M, dyn * P / M) }
        }
        let ctr = mainCore
        let ang = atan2(dyn, dxn)
        for _ in 0..<7 {
            let a = ang + rnd(-0.5, 0.5), sp = rnd(120, 340)
            puffs.append(Puff(x: ctr.pos.x + dxn * ctr.r, y: ctr.pos.y + dyn * ctr.r, vx: cos(a) * sp, vy: sin(a) * sp, life: 1))
        }
    }

    private func ejectInDirection(_ dxIn: Float, _ dyIn: Float) {
        var len = hypot(dxIn, dyIn); if len == 0 { len = 1 }
        let dxn = dxIn / len, dyn = dyIn / len
        let ctr = mainCore
        var best = -1
        var bestProj = -Float.infinity
        for o in 0..<count where bodies[o].type == BodyType.atom && bodies[o].isMine {
            let px = dx(bodies[o].pos.x, ctr.pos.x), py = dy(bodies[o].pos.y, ctr.pos.y)
            let proj = px * dxn + py * dyn
            if proj > bestProj { bestProj = proj; best = o }
        }
        if best < 0 { energyPulse(dxn, dyn); return }
        doEject(best, dxn, dyn)
    }

    private func ejectAtPoint(_ wx: Float, _ wy: Float) {
        var best = -1
        var bestD = Float.infinity
        for o in 0..<count where bodies[o].type == BodyType.atom && bodies[o].isMine {
            let ddx = dx(bodies[o].pos.x, wx), ddy = dy(bodies[o].pos.y, wy)
            let d = ddx * ddx + ddy * ddy
            if d < bestD { bestD = d; best = o }
        }
        if best < 0 {
            let c0 = mainCore
            energyPulse(dx(wx, c0.pos.x), dy(wy, c0.pos.y))
            return
        }
        var ddx = dx(wx, bodies[best].pos.x), ddy = dy(wy, bodies[best].pos.y)
        var len = hypot(ddx, ddy); if len == 0 { len = 1 }
        ddx /= len; ddy /= len
        doEject(best, ddx, ddy)
    }

    private func processEjectQueue() {
        if ejectQueue.isEmpty { return }
        for d in ejectQueue {
            if d.point { ejectAtPoint(d.x, d.y) } else { ejectInDirection(d.x, d.y) }
        }
        ejectQueue.removeAll(keepingCapacity: true)
    }

    // MARK: - Щупы: ловят комки пыли, бросок только с щупа
    //
    // Комок на щупе = ядро + остальные зёрна. Ядро (первое зерно) щуп жёстко держит ровно в точке своего
    // конца. Остальные — обычные тела: их удерживает притяжение конца щупа и липкий контакт друг с другом.

    /// Отпустить всё, что держит щуп s, без броска.
    private func releaseProbe(_ s: Int) {
        for j in held[s] { bodies[j].flags &= ~BodyFlag.group }
        held[s] = []
        holdOrder.removeAll { $0 == s }
    }

    private var heldSet: Set<Int> {
        var set = Set<Int>()
        for clump in held { set.formUnion(clump) }
        return set
    }

    /// Мировая позиция конца щупа s.
    private func probeTip(_ s: Int, length: Float) -> SIMD2<Float> {
        let a = bodies[0].ang + cores[0].slots[s]
        return bodies[0].pos + SIMD2<Float>(cos(a), sin(a)) * length
    }

    private func updateHolds() {
        guard let pr = round.probes, !bodies[0].isCaptured else { return }
        // зерно комка, отнесённое далеко от конца щупа, отваливается
        for s in 0..<held.count where !held[s].isEmpty {
            let tip = probeTip(s, length: pr.length)
            var kept: [Int] = []
            for j in held[s] {
                let ddx = dx(bodies[j].pos.x, tip.x), ddy = dy(bodies[j].pos.y, tip.y)
                if ddx * ddx + ddy * ddy > pr.dropR * pr.dropR || bodies[j].isCaptured {
                    bodies[j].flags &= ~BodyFlag.group
                } else {
                    kept.append(j)
                }
            }
            held[s] = kept
            if kept.isEmpty { holdOrder.removeAll { $0 == s } }
        }
        // перезарядка щупов после выстрела
        for s in 0..<probeReload.count where probeReload[s] > 0 { probeReload[s] = max(0, probeReload[s] - K.DT) }

        // рост: зерно цепляется, только КОСНУВШИСЬ ядрышка на конце щупа или уже прицепившегося зерна
        let usedByBonds = Set(cores[0].bonds.values)
        var taken = heldSet
        for s in 0..<held.count where !physOff(s) && !usedByBonds.contains(s) && probeReload[s] <= 0 {
            if held[s].count >= pr.maxClump { continue }
            let n = nuclei[s]
            for o in cores.count..<count where bodies[o].type == BodyType.dust {
                if held[s].count >= pr.maxClump { break }
                if bodies[o].heat > 0 || bodies[o].isCaptured || taken.contains(o) { continue }
                let ndx = dx(bodies[o].pos.x, bodies[n].pos.x), ndy = dy(bodies[o].pos.y, bodies[n].pos.y)
                let nReach = (bodies[o].r + bodies[n].r) * pr.linkGap
                var touches = ndx * ndx + ndy * ndy <= nReach * nReach
                if !touches {
                    for j in held[s] {
                        let ddx = dx(bodies[o].pos.x, bodies[j].pos.x), ddy = dy(bodies[o].pos.y, bodies[j].pos.y)
                        let reach = (bodies[o].r + bodies[j].r) * pr.linkGap
                        if ddx * ddx + ddy * ddy <= reach * reach { touches = true; break }
                    }
                }
                if !touches { continue }
                if held[s].isEmpty { holdOrder.append(s) }
                bodies[o].flags |= BodyFlag.member
                bodies[o].kAngle = Float(s)
                taken.insert(o)
                held[s].append(o)
            }
        }
    }

    /// Кнопку щупа s нажали: начинаем отсчёт долгого нажатия.
    func pressBegan(_ s: Int) {
        guard probesOn, s >= 0, s < probePress.count else { return }
        probePress[s] = 0
    }

    /// Кнопку щупа s отпустили: короткое нажатие — выстрел; долгое уже переключило щуп.
    func pressEnded(_ s: Int) {
        guard probesOn, s >= 0, s < probePress.count else { return }
        let t = probePress[s]
        probePress[s] = -1
        if t >= 0 && t != .infinity { throwProbe(s) }
    }

    /// Раз в кадр: дожатое до конца нажатие переключает щуп.
    private func advancePresses(_ dt: Float) {
        guard let pr = round.probes else { return }
        for s in 0..<probePress.count where probePress[s] >= 0 && probePress[s] != .infinity {
            probePress[s] += dt
            if probePress[s] >= pr.holdTime {
                probePress[s] = .infinity
                toggleProbe(s)
            }
        }
    }

    /// Долгое нажатие на кнопку щупа: выключить / включить. Выключенный щуп ничего не ловит;
    /// если на нём висел комок, он отпускается без броска.
    func toggleProbe(_ s: Int) {
        guard probesOn, s >= 0, s < probeOff.count, !winning else { return }
        probeOff[s].toggle()
        if !byDirection && probeOff[s] && !held[s].isEmpty { releaseProbe(s) }
    }

    /// Выстреленная копия ядрышка: обычное зерно пыли в точке конца щупа. Не больше 120 штук в мире —
    /// дальше самая старая переиспользуется.
    private func spawnBullet(from n: Int) -> Int? {
        var idx = -1
        if bullets.count >= 120 {
            idx = bullets.removeFirst()
            for s in 0..<held.count { held[s].removeAll { $0 == idx } }
        } else {
            guard count < sim.capacity else { return nil }
            idx = count
            count += 1
        }
        var b = Body()
        b.type = BodyType.dust
        b.pos = bodies[n].pos
        b.vel = bodies[n].vel
        b.r = bodies[n].r
        b.m = bodies[n].m
        bodies[idx] = b
        bullets.append(idx)
        return idx
    }

    /// Выстрел со щупа s в направлении dir: улетает ядрышко (его копия) вместе со всем, что на нём наросло;
    /// на конце щупа за время перезарядки нарастает новое. Все тела получают одну добавку скорости,
    /// корабль — равный противоположный импульс.
    private func throwClump(_ s: Int, dir: SIMD2<Float>, strength: Float) {
        guard let pr = round.probes, probeReload[s] <= 0 else { return }
        var grains = held[s]
        releaseProbe(s)
        probeReload[s] = pr.reload
        if let bullet = spawnBullet(from: nuclei[s]) { grains.append(bullet) }
        var mass: Float = 0
        for j in grains { mass += bodies[j].m }
        if mass <= 0 { return }
        // скорость вылета не зависит от числа зёрен, поэтому отдача растёт с массой набора:
        // полный комок толкает сильно, одиночное ядрышко — вяло
        let es = pr.throwSpeed * strength
        for j in grains {
            bodies[j].vel += dir * es
            bodies[j].heat = 1
        }
        bodies[0].vel -= dir * (mass * es / bodies[0].m)
        say("flight.moving")
    }

    /// Вариант А: выстрел со щупа s вдоль щупа наружу. Пустой щуп стреляет одним ядрышком.
    func throwProbe(_ s: Int, strength: Float = 1) {
        guard probesOn, s >= 0, s < held.count, !winning, let pr = round.probes else { return }
        if probeOff[s] { return }                          // выключенный щуп (или направление) не реагирует
        // по направлению: кнопка стреляет щупом, который сейчас в её секторе, вдоль него самого —
        // стрелка на кнопке в этот момент показывает ровно туда же
        let s = sectorProbe(s)
        let off = probeTip(s, length: pr.length) - bodies[0].pos
        let len = simd_length(off)
        if len < 0.001 { return }
        // нажатие пускает волну из борта; комок срывается, когда она до него дойдёт (см. advanceShotWaves)
        // настоящая волна уже идёт к этому щупальцу — второе нажатие ничего не добавит
        if shotWaves.contains(where: { $0.slot == s && !$0.fired && !$0.weak }) { return }
        // щупальце ещё восстанавливается: волна холостая — слабая и до него не достаёт. Холостые волны
        // просто накладываются: каждое нажатие пускает свою, прежние дорисовываются до конца
        shotWaves.append(ShotWave(slot: s, strength: strength, out: off / len, t: 0, weak: probeReload[s] > 0))
    }

    /// Раз в кадр: волны идут к своим щупальцам; дошла передняя дуга — щупальце стреляет вдоль себя.
    private func advanceShotWaves(_ dt: Float) {
        guard let pr = round.probes, !shotWaves.isEmpty else { return }
        let host = bodies[0]
        let dist = pr.length - host.r                    // от борта до ядрышка
        let reach = dist * ShotWave.overshoot
        for i in 0..<shotWaves.count {
            // холостая волна (щупальце восстанавливается) короче и толкает во много раз слабее
            let weak = shotWaves[i].weak
            let waveReach = weak ? dist * ShotWave.weakReach : reach
            let power: Float = weak ? ShotWave.weakPower : 1
            let frontBefore = dist * shotWaves[i].t / ShotWave.delay
            shotWaves[i].t += dt
            let front = dist * shotWaves[i].t / ShotWave.delay
            // Волна толкает всё свободное, через что проходит её передняя дуга: каждое тело получает ту же
            // скорость вдоль волны, что и комок со щупальца (дальше ядрышка — слабее, к краю волны до нуля).
            // Корабль получает отдачу от всего, что толкнул.
            let out = shotWaves[i].out
            let origin = host.pos + out * host.r
            var pushed: Float = 0
            for o in cores.count..<count {
                let type = bodies[o].type
                if type != BodyType.dust && type != BodyType.atom { continue }
                if bodies[o].flags & (BodyFlag.group | BodyFlag.captured) != 0 || bodies[o].heat > 0.5 { continue }
                let rel = SIMD2<Float>(dx(bodies[o].pos.x, origin.x), dy(bodies[o].pos.y, origin.y))
                let d = simd_length(rel)
                if d <= frontBefore || d > front || d > waveReach { continue }
                let along = simd_dot(rel, out)
                if along <= 0 || abs(rel.x * out.y - rel.y * out.x) > d * ShotWave.spread { continue }
                var k: Float = 1
                let full = weak ? 0 : dist * ShotWave.fullUntil
                if d > full { k = max(0, 1 - (d - full) / (waveReach - full)) }
                let dv = pr.throwSpeed * shotWaves[i].strength * k * power
                bodies[o].vel += out * dv
                bodies[o].heat = 1
                pushed += bodies[o].m * dv
            }
            if pushed > 0 { bodies[0].vel -= out * (pushed / bodies[0].m) }
            if shotWaves[i].fired { continue }
            if weak {
                // холостая волна щупальце не разряжает, только следит за ним
                let wOff = probeTip(shotWaves[i].slot, length: pr.length) - bodies[0].pos
                let wLen = simd_length(wOff)
                if wLen > 0.001 { shotWaves[i].out = wOff / wLen }
                continue
            }
            let s = shotWaves[i].slot
            let off = probeTip(s, length: pr.length) - bodies[0].pos
            let len = simd_length(off)
            if len > 0.001 { shotWaves[i].out = off / len }          // пока не выстрелило, волна смотрит на щупальце
            if shotWaves[i].t < ShotWave.delay { continue }
            shotWaves[i].fired = true
            if !probeOff[probeSector(s)] && !winning { throwClump(s, dir: shotWaves[i].out, strength: shotWaves[i].strength) }
        }
        shotWaves.removeAll { $0.t >= $0.life }
    }

    /// Вариант Б: свайп — стреляет щуп, лучше всего лежащий по направлению свайпа, в сторону свайпа.
    func throwInDirection(_ dxIn: Float, _ dyIn: Float, strength: Float) {
        guard probesOn, !winning, let pr = round.probes else { return }
        let len = hypot(dxIn, dyIn); if len == 0 { return }
        let dir = SIMD2<Float>(dxIn / len, dyIn / len)
        var bestSlot = -1
        var bestProj = -Float.infinity
        for s in 0..<held.count where !physOff(s) && probeReload[s] <= 0 {
            let off = probeTip(s, length: pr.length) - bodies[0].pos
            let l = simd_length(off)
            if l < 0.001 { continue }
            let proj = simd_dot(off / l, dir)
            if proj > bestProj { bestProj = proj; bestSlot = s }
        }
        if bestSlot < 0 { return }
        throwClump(bestSlot, dir: dir, strength: strength)
    }

    /// «Отклеить последнее»: выстрелить самым свежим комком, корабль получает отдачу.
    func undoLast() {
        guard let s = holdOrder.last else { return }
        throwProbe(s)
    }

    // MARK: - Приток инертонов (обучающие туры)

    private func runSpawner(_ dt: Float) {
        guard let sp = round.spawner, !winning else { return }
        spawnTimer += dt
        if spawnTimer < sp.interval { return }
        if introT < sp.firstDelay { return }          // пауза перед первым прилётом
        spawnTimer -= sp.interval
        guard count < sim.capacity, let ni = elements["nitron"] else { return }
        let host = bodies[0]
        let a = rnd(0, .pi * 2)
        let dir = SIMD2<Float>(cos(a), sin(a))            // от хоста к точке старта
        let start = host.pos + dir * sp.distance
        // к хосту по радиусу + боковая составляющая → спираль; закрутка в случайную сторону
        let tangent = SIMD2<Float>(-dir.y, dir.x)
        let spin: Float = Bool.random() ? 1 : -1
        let relVel = -dir * sp.radialSpeed + tangent * (sp.tangentSpeed * spin)
        var b = Body()
        b.type = BodyType.atom
        b.pos = SIMD2<Float>(Game.wrapCoord(start.x, K.WORLD_W), Game.wrapCoord(start.y, K.WORLD_H))
        b.vel = host.vel + relVel                            // относительно движущегося хоста
        b.m = ni.density * sp.r * sp.r
        b.r = sp.r
        bodies[count] = b
        count += 1
        say("flight.incoming")
    }

    // MARK: - «Свои» (§5/§7) и нестабильность

    func updateMine() {
        for o in 0..<count where bodies[o].type == BodyType.atom { bodies[o].flags &= ~BodyFlag.mine }
        if probesOn { return }      // при щупах «своё» — это комки на щупах (флаг held), а не ближние инертоны
        var queue = body
        var qi = 0
        while qi < queue.count {
            let b = queue[qi]; qi += 1
            let reach = bodies[b].type == BodyType.core ? K.LINK_R : K.LINK_R_ATOM
            let reach2 = reach * reach
            let bp = bodies[b].pos
            for o in 0..<count {
                if bodies[o].type != BodyType.atom || bodies[o].isMine { continue }
                let ddx = dx(bodies[o].pos.x, bp.x), ddy = dy(bodies[o].pos.y, bp.y)
                if ddx * ddx + ddy * ddy <= reach2 {
                    bodies[o].flags |= BodyFlag.mine
                    queue.append(o)
                }
            }
        }
    }

    var explode: ExplodeDef { elements["nitron"]?.explode ?? ExplodeDef(max: 32, r: 35, speed: 4000, burst: 8, rate: 2, rateRef: 16) }

    private func applyInstability(_ dt: Float) {
        burst(type: BodyType.atom, ex: explode, dt: dt)
        if let dex = round.dust?.explode { burst(type: BodyType.dust, ex: dex, dt: dt) }
    }

    // MARK: - Деление больших комков пыли

    private var splitTick = 0
    private var statsSplits = 0
    private var statsMaxClump = 0

    /// Сцепленный комок свободной пыли больше порога делится пополам: случайная линия через центр масс,
    /// половины получают равные противоположные скорости — расходятся двумя кусками, а не пылью.
    private func splitBigClumps() {
        guard let d = round.dust, let limit = d.splitAbove else { return }
        splitTick += 1
        if splitTick % 6 != 0 { return }                 // десять раз в секунду достаточно
        var idx: [Int] = []
        for o in cores.count..<count where bodies[o].type == BodyType.dust
            && bodies[o].flags & (BodyFlag.group | BodyFlag.captured) == 0 { idx.append(o) }
        let n = idx.count
        if n <= limit { return }
        var pos = [SIMD2<Float>](repeating: .zero, count: n)
        var rad = [Float](repeating: 0, count: n)
        for k in 0..<n { pos[k] = bodies[idx[k]].pos; rad[k] = bodies[idx[k]].r }
        // связные компоненты по касанию
        var parent = Array(0..<n)
        for a in 0..<n {
            for b in (a + 1)..<max(a + 1, n) {
                let ddx = Game.wrapDelta(pos[b].x - pos[a].x, Game.HALF_W, K.WORLD_W)
                let ddy = Game.wrapDelta(pos[b].y - pos[a].y, Game.HALF_H, K.WORLD_H)
                let reach = (rad[a] + rad[b]) * d.splitLink
                if ddx * ddx + ddy * ddy > reach * reach { continue }
                var ra = a; while parent[ra] != ra { parent[ra] = parent[parent[ra]]; ra = parent[ra] }
                var rb = b; while parent[rb] != rb { parent[rb] = parent[parent[rb]]; rb = parent[rb] }
                if ra != rb { parent[ra] = rb }
            }
        }
        var comps: [Int: [Int]] = [:]
        for k in 0..<n {
            var r = k; while parent[r] != r { r = parent[r] }
            comps[r, default: []].append(k)
        }
        for (_, members) in comps where members.count > limit {
            // комок, который только что делился или выстрелен, не трогаем
            if members.contains(where: { bodies[idx[$0]].heat > 0 }) { continue }
            let origin = pos[members[0]]
            var centre = SIMD2<Float>.zero
            var rel = [SIMD2<Float>](repeating: .zero, count: members.count)
            for (m, k) in members.enumerated() {
                rel[m] = SIMD2<Float>(Game.wrapDelta(pos[k].x - origin.x, Game.HALF_W, K.WORLD_W),
                                      Game.wrapDelta(pos[k].y - origin.y, Game.HALF_H, K.WORLD_H))
                centre += rel[m]
            }
            centre /= Float(members.count)
            let theta = Float.random(in: 0..<(.pi * 2))
            let normal = SIMD2<Float>(cos(theta), sin(theta))
            // делим по медиане проекции на нормаль: половины равны с точностью до одного зерна
            let order = (0..<members.count).sorted { simd_dot(rel[$0] - centre, normal) < simd_dot(rel[$1] - centre, normal) }
            let half = members.count / 2
            // Скорость разлёта считаем от самого комка: сколько энергии нужно половинам, чтобы уйти из
            // притяжения друг друга. Сила пары G·m·m/(r²+ε²) → её потенциал G·m·m/ε·(π/2 − atan(r/ε)).
            let eps = K.EPS2.squareRoot()
            var bind: Float = 0, massA: Float = 0, massB: Float = 0
            for ra in 0..<half {
                let ka = members[order[ra]]
                let ma = bodies[idx[ka]].m
                massA += ma
                for rb in half..<members.count {
                    let kb = members[order[rb]]
                    let r = simd_length(rel[order[rb]] - rel[order[ra]])
                    bind += K.G * ma * bodies[idx[kb]].m / eps * (.pi / 2 - atan(r / eps))
                }
            }
            for rb in half..<members.count { massB += bodies[idx[members[order[rb]]]].m }
            let reduced = massA * massB / (massA + massB)
            // относительная скорость половин: с запасом над скоростью убегания (вязкость и липкость на разрезе)
            let vRel = max(2 * d.splitSpeed, d.splitBoost * (2 * bind / reduced).squareRoot())
            let vA = vRel * massB / (massA + massB), vB = vRel * massA / (massA + massB)   // импульс сохраняется
            for (rank, m) in order.enumerated() {
                let o = idx[members[m]]
                if rank < half { bodies[o].vel -= normal * vA } else { bodies[o].vel += normal * vB }
                bodies[o].heat = 1
            }
            statsSplits += 1
        }
        statsMaxClump = max(statsMaxClump, comps.values.map { $0.count }.max() ?? 0)
    }

    // ---- отладочная статистика (включается переменной окружения FERM_STATS=1)
    private let statsOn = ProcessInfo.processInfo.environment["FERM_STATS"] == "1"
    private var statsT: Float = 0
    private var statsBursts: [UInt32: Int] = [:]
    private var statsFrames = 0, statsSteps = 0
    private var statsPhysMs: Double = 0, statsGpuMs: Double = 0
    private var statsGpuExecMs: Double = 0, statsGpuQueuedMs: Double = 0
    private let autoFire = ProcessInfo.processInfo.environment["FERM_AUTOFIRE"] == "1"   // замер: игра сама жмёт кнопки
    private let winTest = ProcessInfo.processInfo.environment["FERM_WINTEST"] == "1"     // проверка финала: корабль сам попадает в поглотитель
    private var autoFireT: Float = 0
    private var statsIdleOff = false

    private func printStats(_ dt: Float) {
        guard statsOn else { return }
        if !statsIdleOff { statsIdleOff = true; UIApplication.shared.isIdleTimerDisabled = true }   // замер: экран не гаснет
        if autoFire && probesOn {
            autoFireT += dt
            if autoFireT >= 0.45 { autoFireT = 0; throwProbe(Int.random(in: 0..<held.count)) }
        }
        statsT += dt
        if statsT < 1 { return }
        statsT = 0
        var dust: [Float] = [], atoms: [Float] = []
        var dustEligible = 0, atomsNearHost = 0, dustNearHost = 0
        let host = bodies[0]
        let dexMax = round.dust?.explode?.max ?? 0
        for o in 0..<count {
            let v = simd_length(bodies[o].vel)
            let d = hypot(dx(bodies[o].pos.x, host.pos.x), dy(bodies[o].pos.y, host.pos.y))
            if bodies[o].type == BodyType.dust {
                dust.append(v)
                if Int(bodies[o].nbr) >= dexMax { dustEligible += 1 }
                if d < 80 { dustNearHost += 1 }
            }
            if bodies[o].type == BodyType.atom { atoms.append(v); if d < 80 { atomsNearHost += 1 } }
        }
        dust.sort(); atoms.sort()
        func q(_ a: [Float], _ f: Float) -> Int { a.isEmpty ? 0 : Int(a[min(a.count - 1, Int(Float(a.count) * f))]) }
        print("STATS t=\(Int(roundT)) dust n=\(dust.count) v50=\(q(dust, 0.5)) v90=\(q(dust, 0.9)) v99=\(q(dust, 0.99)) max=\(q(dust, 1)) fast>300=\(dust.filter { $0 > 300 }.count) eligible=\(dustEligible) nearHost=\(dustNearHost) bursts=\(statsBursts[BodyType.dust] ?? 0) | atoms n=\(atoms.count) v90=\(q(atoms, 0.9)) max=\(q(atoms, 1)) nearHost=\(atomsNearHost) bursts=\(statsBursts[BodyType.atom] ?? 0) | hostV=\(Int(simd_length(host.vel))) held=\(held.map { $0.count }) splits=\(statsSplits) maxClump=\(statsMaxClump) | PERF frames=\(statsFrames) steps=\(statsSteps) physMs/step=\(String(format: "%.1f", statsPhysMs / Double(max(1, statsSteps)))) gpuMs/step=\(String(format: "%.1f", statsGpuMs / Double(max(1, statsSteps)))) bodies=\(count)")
        // разбивка для замера: сколько пар тел в радиусе взаимодействия, сколько рядом и сколько в контакте
        var inCut = 0, near = 0, touching = 0
        let cut2 = K.CUT_END * K.CUT_END
        for a in 0..<count {
            for b in (a + 1)..<max(a + 1, count) {
                let ddx = dx(bodies[a].pos.x, bodies[b].pos.x), ddy = dy(bodies[a].pos.y, bodies[b].pos.y)
                let r2 = ddx * ddx + ddy * ddy
                if r2 > cut2 { continue }
                inCut += 1
                if r2 < 200 * 200 { near += 1 }
                let c = bodies[a].r + bodies[b].r
                if r2 < c * c { touching += 1 }
            }
        }
        let pairs = max(1, count * (count - 1) / 2)
        let st = Double(max(1, statsSteps))
        print("PROF t=\(Int(roundT)) bodies=\(count) frames=\(statsFrames) gpuWall=\(String(format: "%.1f", statsGpuMs / st)) gpuExec=\(String(format: "%.1f", statsGpuExecMs / st)) gpuQueued=\(String(format: "%.1f", statsGpuQueuedMs / st)) inCut=\(inCut * 100 / pairs)% near200=\(near) touching=\(touching) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
        statsGpuExecMs = 0; statsGpuQueuedMs = 0
        statsBursts = [:]
        statsFrames = 0; statsSteps = 0; statsPhysMs = 0; statsGpuMs = 0; statsSplits = 0; statsMaxClump = 0
    }

    /// Плотный ком тел данного типа (≥ ex.max соседей) случайно разлетается пачками.
    private func burst(type: UInt32, ex: ExplodeDef, dt: Float) {
        var eligible: [Int] = []
        for o in 0..<count where bodies[o].type == type && Int(bodies[o].nbr) >= ex.max && bodies[o].flags & BodyFlag.group == 0 { eligible.append(o) }   // комок на щупе не взрывается
        if eligible.count < ex.burst { return }
        var expected = ex.rate * dt * (Float(eligible.count) / ex.rateRef)
        while expected > 0 {
            if expected < 1 && Float.random(in: 0..<1) >= expected { break }
            for _ in 0..<ex.burst {
                let A = eligible[Int.random(in: 0..<eligible.count)]
                if bodies[A].heat > 0 { continue }      // уже выбито: одно тело не получает несколько толчков подряд
                let ang = Float.random(in: 0..<(.pi * 2))
                bodies[A].vel += SIMD2<Float>(cos(ang) * ex.speed, sin(ang) * ex.speed)
                bodies[A].heat = 1
            }
            statsBursts[type, default: 0] += 1
            expected -= 1
        }
    }

    // MARK: - Шаг физики за кадр

    private func makeParams(hSub: Float) -> SimParams {
        var p = SimParams()
        p.bodyCount = UInt32(count)
        p.coreCount = UInt32(cores.count)
        p.hSub = hSub
        p.G = K.G; p.EPS2 = K.EPS2; p.CUT_START = K.CUT_START; p.CUT_END = K.CUT_END
        p.K_REP = K.K_REP; p.V_STICK = K.V_STICK; p.STICK_MIN = K.STICK_MIN
        p.BOND_DAMP = K.BOND_DAMP; p.K_ANGLE = K.K_ANGLE; p.K_ANGLE_TORQUE = K.K_ANGLE_TORQUE; p.ANG_DAMP = K.ANG_DAMP
        p.MAX_SPEED = round.maxSpeed ?? K.MAX_SPEED; p.VISCOSITY = round.viscosity ?? K.VISCOSITY; p.INSTAB_R = explode.r
        p.bubbleR2 = (K.R_CORE * K.GRAV_OFF_R_MULT) * (K.R_CORE * K.GRAV_OFF_R_MULT)
        p.gravBubbleOn = gravBubbleOn ? 1 : 0
        p.worldSize = SIMD2<Float>(K.WORLD_W, K.WORLD_H)
        p.zonePos = SIMD2<Float>(zone.x, zone.y)
        p.zoneMass = zone.m
        if let pr = round.probes {
            p.holdOn = 1
            p.holdK = pr.k
            p.holdLen = pr.length
            p.hostSpin = pr.spin
            p.holdDamp = pr.damp
            p.heldGravity = pr.heldGravity
            p.hostGravity = pr.hostGravity
            p.memberPull = pr.memberPull
        }
        return p
    }

    private func stepPhysics(_ dt: Float) {
        computeBody()
        if !bodies[0].isCaptured { bodies[0].r = max(3, K.R_CORE * bodies[0].m / K.M_CORE) }
        if gravMode == -1 {
            pulseTimer += dt
            if pulseTimer >= K.PULSE_PERIOD { pulseTimer -= K.PULSE_PERIOD }
        }
        gravBubbleOn = gravMode == 1 || (gravMode == -1 && pulseTimer >= K.PULSE_PERIOD * 0.5)
        processEjectQueue()
        updateBonds()
        updateHolds()
        if winning {
            zone.bhT += dt
            zone.m = min(K.BH_MAX, K.BH_MAX * zone.bhT / K.BH_RAMP)
        }
        syncBondsToGPU()
        let substeps = round.substeps ?? K.SUBSTEPS
        let h = dt * K.TIME_SCALE / Float(substeps)
        let gpuT0 = CACurrentMediaTime()
        sim.run(params: makeParams(hSub: h), substeps: substeps)
        statsGpuMs += (CACurrentMediaTime() - gpuT0) * 1000
        statsGpuExecMs += sim.lastGpuExec * 1000
        statsGpuQueuedMs += sim.lastGpuQueued * 1000

        // ядрышко на конце щупа стоит намертво, пока его не выстрелили: после каждого шага возвращаем его
        // точно на место (длина и угол покоя лежат в самом теле) со скоростью конца щупа — удары его не сбивают
        if let pr = round.probes {
            let host = bodies[0]
            for n in nuclei {
                let a = host.ang + bodies[n].ang, L = bodies[n].angVel
                let dir = SIMD2<Float>(cos(a), sin(a))
                bodies[n].pos = host.pos + dir * L
                bodies[n].vel = host.vel + SIMD2<Float>(-dir.y, dir.x) * (pr.spin * L)
            }
        }

        for o in 0..<count where bodies[o].type != BodyType.anchor {
            bodies[o].pos.x = Game.wrapCoord(bodies[o].pos.x, K.WORLD_W)
            bodies[o].pos.y = Game.wrapCoord(bodies[o].pos.y, K.WORLD_H)
            if bodies[o].heat > 0 { bodies[o].heat -= dt / K.EJECT_FADE }
        }
        updateMine()
        if round.narration {
            if probesOn {
                if held.contains(where: { !$0.isEmpty }) { say("flight.caught") }
            } else {
                for o in 0..<count where bodies[o].type == BodyType.atom && bodies[o].isMine { say("flight.caught"); break }
            }
        }
        applyInstability(dt)
        splitBigClumps()
        runSpawner(dt)
        printStats(dt)
    }

    // MARK: - Победа

    private func inZone(_ c: Int) -> Bool {
        let ddx = dx(bodies[c].pos.x, zone.x), ddy = dy(bodies[c].pos.y, zone.y)
        return ddx * ddx + ddy * ddy <= zone.r * zone.r
    }

    private func partners(_ c: Int, kind: String) -> [Int] {
        cores[c].bonds.keys.filter { cores[$0].kind == kind }
    }

    /// Собранная ЧИСТАЯ молекула текущего раунда (без хоста) → индексы её ядер, или nil.
    private func findMolecule() -> [Int]? {
        if round.win == .benzene {
            // «углерод» кольца: trigen, насыщен, ровно 2 trigen-соседа + 1 capsor
            func isC(_ c: Int?) -> Bool {
                guard let c else { return false }
                return cores[c].kind == "trigen" && cores[c].bonds.count == 3
                    && partners(c, kind: "trigen").count == 2 && partners(c, kind: "capsor").count == 1
            }
            for start in 0..<cores.count where isC(start) {
                var ring = [start]
                var prev = start
                var cur: Int? = partners(start, kind: "trigen").first(where: { isC($0) })
                while let c = cur, isC(c), c != start, ring.count < 6 {
                    ring.append(c)
                    let next = partners(c, kind: "trigen").first(where: { $0 != prev && isC($0) })
                    prev = c; cur = next
                }
                if cur == start && ring.count == 6 {
                    let caps = ring.compactMap { partners($0, kind: "capsor").first }
                    if caps.count == 6 { return ring + caps }
                }
            }
            return nil
        }
        for hub in 0..<cores.count {
            if cores[hub].kind != "trigen" || cores[hub].bonds.count != cores[hub].valence { continue }
            let ps = Array(cores[hub].bonds.keys)
            if ps.allSatisfy({ cores[$0].kind == "capsor" }) { return [hub] + ps }
        }
        return nil
    }

    private func checkWin() {
        if won || winning { assembled = false; return }
        if round.win == .reachZone {
            // обучение: хост долетел до поглотителя → всасывается сам
            assembled = false
            if !inZone(0) { return }
            winning = true
            zone.bhT = 0
            winMol = [0]
            say("flight.done")
            bodies[0].flags |= BodyFlag.captured | BodyFlag.molCore
            bodies[0].r0 = bodies[0].r
            bodies[0].cap = 0
            bodies[0].vel = .zero
            cores[0].bonds = [:]
            cores[0].slots = []
            return
        }
        guard let mol = findMolecule() else { assembled = false; return }
        assembled = true
        if !mol.allSatisfy({ inZone($0) }) { return }
        winning = true
        zone.bhT = 0
        winMol = mol
        for c in mol {
            bodies[c].flags |= BodyFlag.captured | BodyFlag.molCore
            bodies[c].r0 = bodies[c].r
            bodies[c].cap = 0
            bodies[c].vel = .zero
            cores[c].bonds = [:]
            cores[c].slots = []
        }
    }

    /// ФАЗА 1: молекула и всё, что попало в поглотитель, белеет, усыхает до 10% и тянется к центру.
    private func advanceCapture(_ dt: Float) {
        if !winning { return }
        let DUR: Float = 1.0
        let zr2 = zone.r * zone.r
        for o in 0..<count {
            if bodies[o].isCaptured || bodies[o].type == BodyType.anchor { continue }
            let ddx = dx(zone.x, bodies[o].pos.x), ddy = dy(zone.y, bodies[o].pos.y)
            if ddx * ddx + ddy * ddy < zr2 {
                bodies[o].flags |= BodyFlag.captured
                bodies[o].r0 = bodies[o].r
                bodies[o].cap = 0
                bodies[o].vel = .zero
            }
        }
        for o in 0..<count where bodies[o].isCaptured {
            let tox = dx(zone.x, bodies[o].pos.x), toy = dy(zone.y, bodies[o].pos.y)
            bodies[o].vel += SIMD2<Float>(tox * 36 * dt, toy * 36 * dt)
            bodies[o].vel *= max(0, 1 - 12 * dt)
            let dur = bodies[o].isMolCore ? DUR : DUR * 1
            bodies[o].cap = min(1, bodies[o].cap + dt / dur)
            bodies[o].r = bodies[o].r0 * (1 - 0.9 * bodies[o].cap)
        }
        if !won && !winMol.isEmpty && winMol.allSatisfy({ bodies[$0].cap >= 1 }) {
            won = true
            winBannerT = 0
        }
    }

    // MARK: - Кадр

    func frame(now: Double) {
        let rawElapsed = Float(now - last); last = now
        if !introHold { introT += rawElapsed }
        if winTest && introT > 6 && !winning && !won { bodies[0].pos = SIMD2<Float>(zone.x + zone.r * 0.6, zone.y); bodies[0].vel = .zero }
        if !won { roundT += rawElapsed }
        advanceShotWaves(rawElapsed)
        if !puffs.isEmpty {
            for i in 0..<puffs.count {
                puffs[i].x += puffs[i].vx * rawElapsed
                puffs[i].y += puffs[i].vy * rawElapsed
                puffs[i].life -= rawElapsed / 0.35
            }
            puffs.removeAll { $0.life <= 0 }
        }
        var elapsed = rawElapsed
        if elapsed > 0.05 { elapsed = 0.05 }
        acc += elapsed
        var steps = 0
        while acc >= K.DT && steps < 3 {      // не больше трёх шагов на кадр: под нагрузкой игра замедляется, а не захлёбывается
            let t0 = CACurrentMediaTime()
            stepPhysics(K.DT); acc -= K.DT; steps += 1
            statsPhysMs += (CACurrentMediaTime() - t0) * 1000; statsSteps += 1
        }
        statsFrames += 1
        if steps == 3 { acc = 0 }
        if winning { advanceCapture(elapsed) }
        if !won { checkWin() }
        if winBannerT >= 0 {
            winBannerT += rawElapsed
            if winBannerT >= 3 { winBannerT = -1; hud.showWin = true }
        }
        gfxSpin += 0.05
        advancePresses(rawElapsed)
        updateStarMirror()
        for s in 0..<probePulse.count where probePulse[s] > 0 { probePulse[s] = max(0, probePulse[s] - rawElapsed / 0.28) }
        // реплика про включение: появляется чуть раньше, чем корабль начинает светлеть, висит, пока он
        // разгорается, и гаснет сразу после (последняя секунда показа — затухание)
        if introT >= K.SHIP_ON_DELAY - K.POWER_LINE_LEAD {
            say("flight.power", show: K.POWER_LINE_LEAD + K.SHIP_ON_TIME + K.POWER_LINE_TAIL)
        }
        if shipOn >= 1 { say("flight.start") }
        // реплика про стрелку — после паузы за погасшей репликой про включение; чуть позже стрелку обводят
        let arrowAt = K.SHIP_ON_DELAY + K.SHIP_ON_TIME + K.POWER_LINE_TAIL + K.ARROW_LINE_PAUSE
        if introT >= arrowAt { say("flight.arrow") }
        if round.narration && !chalkDone && introT >= arrowAt + K.CHALK_DELAY { chalkDone = true; chalkT = 0 }
        if chalkT >= 0 {
            chalkT += rawElapsed
            if chalkT > Game.chalkLife { chalkT = -1 }
        }
        advanceNarration()

        fpsAcc += rawElapsed; fpsFrames += 1
        if fpsAcc >= 0.5 { fps = Float(fpsFrames) / fpsAcc; fpsAcc = 0; fpsFrames = 0 }
        updateHud()
    }

    // MARK: - HUD (§7)

    private func updateHud() {
        var mine = 0
        for o in 0..<count where bodies[o].type == BodyType.atom && bodies[o].isMine { mine += 1 }
        var vs = SIMD2<Float>.zero
        for c in 0..<cores.count { vs += bodies[c].vel }
        let speed = simd_length(vs / Float(max(1, cores.count)))
        let host = bodies[0]
        let names: [Int: String] = [-1: "ПУЛЬСАР", 0: "норма", 1: "ВЫКЛ"]
        var goodBonds = 0
        for c in 0..<cores.count where cores[c].kind == "trigen" {
            goodBonds = max(goodBonds, partners(c, kind: "capsor").count)
        }
        let inBodySet = Set(body)
        let hubsInBody = (0..<cores.count).filter { cores[$0].kind == "trigen" && inBodySet.contains($0) }.count
        let capsInBody = (0..<cores.count).filter { cores[$0].kind == "capsor" && inBodySet.contains($0) }.count
        let haveAll = hubsInBody >= 1 && capsInBody >= K.N_CAP
        let tm = Int(roundT / 60), ts = Int(roundT) % 60

        let h = hud
        set(&h.time, "\(tm):" + String(format: "%02d", ts))
        set(&h.speed, Int(simd_length(host.vel).rounded()))
        set(&h.valence, cores[0].valence)
        set(&h.mass, Int(host.m.rounded()))
        set(&h.bonds, cores[0].bonds.count)
        set(&h.gravName, names[gravMode] ?? "норма")
        set(&h.gravIsNorm, gravMode == 0)
        set(&h.mine, mine)
        set(&h.goodBonds, goodBonds)
        let status: MoleculeStatus = assembled ? .assembled : (haveAll ? .haveAll : .notAssembled)
        set(&h.molStatus, status)
        set(&h.probesOn, probesOn)
        set(&h.probeFill, (0..<held.count).map { s -> Float in
            // щуп может выстрелить — показываем, сколько на нём: одно своё ядрышко уже заметно, 12 зёрен — полная
            let p = sectorProbe(s)
            // по направлению кнопка стоит неподвижно: одна ровная яркость, что бы ни проезжало через её сектор
            if byDirection { return probeOff[s] ? 0 : 0.6 }
            guard let pr = round.probes, !probeOff[s], probeReload[p] <= 0 else { return 0 }
            return 0.2 + 0.8 * min(1, Float(held[p].count) / Float(max(1, pr.maxClump)))
        })
        set(&h.probeOff, probeOff)
        // восстановление после выстрела: 0 сразу после, 1 — щупальце снова готово (кнопка набирает цвет)
        set(&h.probeCharge, (0..<held.count).map { s -> Float in
            let p = sectorProbe(s)
            guard let pr = round.probes, pr.reload > 0 else { return 1 }
            return 1 - min(1, max(0, probeReload[p] / pr.reload))
        })
        // стрелка кнопки показывает середину её сектора. Углы отдаём «развёрнутыми» — каждый раз идём к новому
        // значению кратчайшей дугой, — чтобы при зеркальном перевороте ряда стрелка плавно доворачивалась, а не
        // крутилась через полный круг
        if byDirection {
            let n = cores[0].slots.count
            if arrowShown.count != n { arrowShown = (0..<n).map { arrowAngle($0) } }
            for k in 0..<n {
                var d = (arrowAngle(k) - arrowShown[k]).truncatingRemainder(dividingBy: 2 * .pi)
                if d > .pi { d -= 2 * .pi }
                if d < -.pi { d += 2 * .pi }
                arrowShown[k] += d
            }
        }
        set(&h.probeArrows, byDirection ? arrowShown : [])
        set(&h.probeMirror, starMirrored)
        set(&h.probeColorOffset, round.probes?.colorOffset ?? 0)
        set(&h.probeHold, (0..<probeOff.count).map { probeHoldProgress($0) })
        set(&h.controlMode, controlMode)
        set(&h.showDebug, showDebug)
        set(&h.showBonds, showBonds)
        set(&h.ejectModeName, ejectMode.rawValue)
        if showDebug {
            var free = 0
            for o in 0..<count where bodies[o].type == BodyType.atom && !bodies[o].isMine { free += 1 }
            set(&h.debugLine1, "FPS \(Int(fps)) · объектов \(count) (свободных \(free)) · |v| \(Int(speed))")
            set(&h.debugLine2, "выброс: \(ejectMode.rawValue) · G \(Int(K.G)) · K_rep \(Int(K.K_REP)) · stick \(K.STICK_MIN)/\(Int(K.V_STICK)) · visc \(K.VISCOSITY) · time \(K.TIME_SCALE) · subst \(K.SUBSTEPS) · eject \(Int(K.EJECT_SPEED))")
        }
        var intro: Double = 0
        if introT < 8 && !won { intro = introT > 6 ? Double((8 - introT) / 2) : 1 }
        set(&h.introOpacity, max(0, intro))
    }

    private func set<T: Equatable>(_ slot: inout T, _ value: T) {
        if slot != value { slot = value }
    }

    // MARK: - Ввод

    /// Тап по экрану: мировая точка (хост в центре экрана) → выстрел ближайшим инертоном.
    func tap(at point: CGPoint, viewSize: CGSize, scale: Float) {
        if probesOn { return }          // управление без тапов: кнопки щупов или свайп
        let cam = mainCore
        let wx = cam.pos.x + Float(point.x - viewSize.width / 2) / scale
        let wy = cam.pos.y + Float(point.y - viewSize.height / 2) / scale
        ejectQueue.append(EjectRequest(point: true, x: wx, y: wy))
    }

    func press(_ key: HudKey) {
        switch key {
        case .massUp: bodies[0].m = min(K.MASS_MAX, bodies[0].m + K.MASS_STEP)
        case .massDown: bodies[0].m = max(K.MASS_MIN, bodies[0].m - K.MASS_STEP)
        case .gravRight: gravMode = min(gravMode + 1, 1); pulseTimer = 0
        case .gravLeft: gravMode = max(gravMode - 1, -1); pulseTimer = 0
        case .valenceDown: setValence(0, cores[0].valence - 1)
        case .valenceUp: setValence(0, cores[0].valence + 1)
        case .toggleDebug: showDebug.toggle()
        case .toggleEjectMode: ejectMode = ejectMode == .intoCore ? .opposite : .intoCore
        case .toggleBonds: showBonds.toggle()
        case .restart: setup()
        case .nextRound:
            if Progress.hasNext { Progress.roundIndex += 1 }
            setup()
        }
    }
}
