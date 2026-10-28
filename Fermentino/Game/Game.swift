//
//  Game.swift
//  Fermentino
//
//  Перенос игровой логики веб-прототипа (dev-версия) один в один: тела живут в общем буфере
//  GPU, вся логика раунда (связи, выброс, «свои», нестабильность, победа) — здесь, на CPU.
//

import Foundation
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

    // ---- реплики диспетчерской (обучение)
    private var narrationQueue: [String] = []
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
    private(set) var assembled = false
    private(set) var roundT: Float = 0
    private(set) var puffs: [Puff] = []
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
        won = false; winning = false; winMol = []; winBannerT = -1; introT = 0; assembled = false; roundT = 0; puffs = []
        hud.showWin = false
        hud.winKind = round.win
        hud.introLines = round.intro.map { Strings.t($0) }
        hud.introIcon = round.introIcon
        hud.winSub = Strings.t(round.winSub)
        narrationQueue = []; narrationShownAt = -1; said = []
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
            for _ in 0..<d.n {
                guard count < sim.capacity else { break }
                var b = Body()
                b.type = BodyType.dust
                b.pos = SIMD2<Float>(rnd(0, K.WORLD_W), rnd(0, K.WORLD_H))
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
        say("flight.start")
    }

    // MARK: - Реплики по событиям

    /// Сказать реплику один раз за раунд (только в турах с нарративом).
    private func say(_ key: String) {
        guard round.narration, !said.contains(key) else { return }
        said.insert(key)
        narrationQueue.append(Strings.t(key))
    }

    private func advanceNarration() {
        // время показа по длине текста: ~14 знаков в секунду, не меньше 3 с; следующая реплика
        // не вытесняет текущую, пока та не дочитана
        let fade: Float = 1.0
        let minShow = max(3.0, Float(hud.narration.count) / 14.0)
        let maxShow = minShow + 2.5
        let shown = introT - narrationShownAt
        let hasCurrent = narrationShownAt >= 0 && shown < maxShow
        if !narrationQueue.isEmpty && (!hasCurrent || shown >= minShow) {
            hud.narration = narrationQueue.removeFirst()
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

    private func doEject(_ best: Int, _ dxn: Float, _ dyn: Float) {
        bodies[best].heat = 1
        say("flight.moving")
        let es = K.EJECT_SPEED * sqrt(1 + Float(yellowCount) * K.ENERGY_PER_YELLOW) * (K.EJECT_REF_MASS / bodies[best].m)
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
        let ex = explode
        var eligible: [Int] = []
        for o in 0..<count where bodies[o].type == BodyType.atom && Int(bodies[o].nbr) >= ex.max { eligible.append(o) }
        if eligible.count < ex.burst { return }
        var expected = ex.rate * dt * (Float(eligible.count) / ex.rateRef)
        while expected > 0 {
            if expected < 1 && Float.random(in: 0..<1) >= expected { break }
            for _ in 0..<ex.burst {
                let A = eligible[Int.random(in: 0..<eligible.count)]
                let ang = Float.random(in: 0..<(.pi * 2))
                bodies[A].vel += SIMD2<Float>(cos(ang) * ex.speed, sin(ang) * ex.speed)
                bodies[A].heat = 1
            }
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
        p.MAX_SPEED = K.MAX_SPEED; p.VISCOSITY = round.viscosity ?? K.VISCOSITY; p.INSTAB_R = explode.r
        p.bubbleR2 = (K.R_CORE * K.GRAV_OFF_R_MULT) * (K.R_CORE * K.GRAV_OFF_R_MULT)
        p.gravBubbleOn = gravBubbleOn ? 1 : 0
        p.worldSize = SIMD2<Float>(K.WORLD_W, K.WORLD_H)
        p.zonePos = SIMD2<Float>(zone.x, zone.y)
        p.zoneMass = zone.m
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
        if winning {
            zone.bhT += dt
            zone.m = min(K.BH_MAX, K.BH_MAX * zone.bhT / K.BH_RAMP)
        }
        syncBondsToGPU()
        let h = dt * K.TIME_SCALE / Float(K.SUBSTEPS)
        sim.run(params: makeParams(hSub: h), substeps: K.SUBSTEPS)

        for o in 0..<count where bodies[o].type != BodyType.anchor {
            bodies[o].pos.x = Game.wrapCoord(bodies[o].pos.x, K.WORLD_W)
            bodies[o].pos.y = Game.wrapCoord(bodies[o].pos.y, K.WORLD_H)
            if bodies[o].heat > 0 { bodies[o].heat -= dt / K.EJECT_FADE }
        }
        updateMine()
        if round.narration {
            for o in 0..<count where bodies[o].type == BodyType.atom && bodies[o].isMine { say("flight.caught"); break }
        }
        applyInstability(dt)
        runSpawner(dt)
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
        introT += rawElapsed
        if !won { roundT += rawElapsed }
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
        while acc >= K.DT && steps < 5 { stepPhysics(K.DT); acc -= K.DT; steps += 1 }
        if steps == 5 { acc = 0 }
        if winning { advanceCapture(elapsed) }
        if !won { checkWin() }
        if winBannerT >= 0 {
            winBannerT += rawElapsed
            if winBannerT >= 3 { winBannerT = -1; hud.showWin = true }
        }
        gfxSpin += 0.05
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
