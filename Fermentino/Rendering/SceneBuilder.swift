//
//  SceneBuilder.swift
//  Fermentino
//
//  Перенос draw() прототипа: из состояния игры собирает список фигур и линий
//  в экранных точках (камера на хосте, мир заворачивается).
//

import Foundation
import simd

struct RenderScene {
    var shapes: [ShapeInstance] = []
    var lines: [LineVertex] = []
    var zoneLabel: CGPoint? = nil
}

struct SceneBuilder {
    let game: Game
    let w: Float
    let h: Float
    let scale: Float
    private(set) var scene = RenderScene()

    private var cx: Float { w / 2 }
    private var cy: Float { h / 2 }
    // поворот вида вокруг корабля: косинус и синус угла game.viewRot
    private let rc: Float
    private let rs: Float
    /// Экранное смещение, повёрнутое вместе с видом.
    private func rot(_ ox: Float, _ oy: Float) -> SIMD2<Float> {
        SIMD2<Float>(rc * ox - rs * oy, rs * ox + rc * oy)
    }

    init(game: Game, size: CGSize, scale: Float) {
        self.game = game
        self.w = Float(size.width)
        self.h = Float(size.height)
        self.scale = scale
        self.rc = cos(game.viewRot)
        self.rs = sin(game.viewRot)
        scene.shapes.reserveCapacity(game.count * 2 + 800)
    }

    // MARK: - примитивы

    private mutating func circle(_ x: Float, _ y: Float, _ r: Float, _ color: SIMD4<Float>, inner: Float = 0, soft: Float = 0) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.radius = r
        s.inner = inner
        s.color = color
        s.shape = 0
        s.soft = soft
        scene.shapes.append(s)
    }

    private mutating func star(_ x: Float, _ y: Float, _ outer: Float, inner: Float, _ color: SIMD4<Float>, angle: Float = 0, gradient: Float = 0) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.halfSize = SIMD2<Float>(angle, gradient)   // для звезды: угол поворота и сила градиента вдоль главного луча
        s.radius = outer
        s.inner = inner / outer      // для звезды: отношение внутреннего радиуса к внешнему
        s.color = color
        s.shape = 2
        scene.shapes.append(s)
    }

    /// Клин компаса: полуширина w, высота h, угол поворота, расстояние от его основания до центра корабля.
    private mutating func arrow(_ x: Float, _ y: Float, halfWidth: Float, height: Float, angle: Float, ringR: Float, _ color: SIMD4<Float>) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.radius = halfWidth
        s.inner = height
        s.halfSize = SIMD2<Float>(angle, ringR)
        s.color = color
        s.shape = 3
        scene.shapes.append(s)
    }

    /// Корпус корабля: железный шар со швами, заклёпками и ржавчиной, рисунок повёрнут на angle.
    /// rust — сила ржавчины: 1 — ржавый, 0 — ровный круг цвета color.
    private mutating func hull(_ x: Float, _ y: Float, _ r: Float, _ color: SIMD4<Float>, angle: Float, rust: Float) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.radius = r
        s.halfSize = SIMD2<Float>(angle, rust)
        s.color = color
        s.shape = 6
        scene.shapes.append(s)
    }

    /// Метка на ободе: кусок кольца вокруг (x, y) между радиусами inner и outer, с прямыми боками,
    /// ось смотрит под углом angle, полуширина halfWidth.
    private mutating func rimMark(_ x: Float, _ y: Float, inner: Float, outer: Float, angle: Float, halfWidth: Float, _ color: SIMD4<Float>) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.radius = outer
        s.inner = inner
        s.halfSize = SIMD2<Float>(angle, halfWidth)
        s.color = color
        s.shape = 5
        scene.shapes.append(s)
    }

    private mutating func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: SIMD4<Float>) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x + w / 2, y + h / 2)
        s.halfSize = SIMD2<Float>(w / 2, h / 2)
        s.color = color
        s.shape = 1
        scene.shapes.append(s)
    }

    private mutating func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ color: SIMD4<Float>) {
        var a = LineVertex(); a.pos = SIMD2<Float>(x1, y1); a.color = color
        var b = LineVertex(); b.pos = SIMD2<Float>(x2, y2); b.color = color
        scene.lines.append(a); scene.lines.append(b)
    }

    /// Экранная позиция тела относительно камеры (ближайший образ).
    private func screen(_ x: Float, _ y: Float, cam: SIMD2<Float>) -> SIMD2<Float> {
        let o = rot(game.dx(x, cam.x) * scale, game.dy(y, cam.y) * scale)
        return SIMD2<Float>(cx + o.x, cy + o.y)
    }

    // MARK: - объекты

    private mutating func drawBody(_ i: Int, cam: SIMD2<Float>) {
        let o = game.bodies[i]
        let p = screen(o.pos.x, o.pos.y, cam: cam)
        let marginX = cx + 80 * scale, marginY = cy + 80 * scale
        if p.x < cx - marginX || p.x > cx + marginX || p.y < cy - marginY || p.y > cy + marginY { return }
        let r = o.r * scale

        if o.type == BodyType.dust {
            var t: Float = 0
            if let dex = game.round.dust?.explode { t = min(1, Float(o.nbr) / Float(dex.max)) }
            var col = mixCol(K.COL_ATOM, max(o.heat, t)); col.w = 0.7
            circle(p.x, p.y, r, col)
            return
        }
        if o.type == BodyType.anchor {
            circle(p.x, p.y, r, K.COL_ANCHOR)
            circle(p.x - r * 0.3, p.y - r * 0.3, r * 0.6, K.COL_ANCHOR_EDGE, soft: 1)
            circle(p.x, p.y, r, rgb("#2a2620"), inner: r - 2)
            return
        }
        if o.type == BodyType.core {
            let c = game.cores[i]
            var col = c.col
            var on: Float = 1                                // корабль: насколько он «включился» с начала тура
            if c.main { on = game.shipOn; col = game.hullColor }
            if o.cap > 0 { col = col + (SIMD4<Float>(1, 1, 1, 1) - col) * o.cap; col.w = 1 }
            var fade: Float = 1                              // корабль в поглотителе: под конец тает до прозрачного
            if c.main { fade = game.shipFade; col.w = fade }
            if fade <= 0 { return }
            let spin = game.gfxSpin * 0.8 + c.spinPhase      // 0.8 — скорость вращения электронов
            let orbitR = r * 0.7                               // 0.7 — радиус орбиты (ближе к краю)
            var n = max(0, c.valence - c.bonds.count)
            if c.main && game.probesOn { n = 0 }           // у хоста свободные щупы рисуются штырями, не электронами
            let blur: Float = c.main ? 14 : 10
            var glow = col; glow.w = 0.55
            if c.main { glow.w = (0.12 + 0.5 * on) * fade } // ржавый почти не светится, свечение приходит с включением
            circle(p.x, p.y, r + blur * scale, glow, soft: 1)
            if c.main {
                // пока корабль не включился, он ржавый: швы, заклёпки и разводы вращаются вместе с ним;
                // с включением всё это сходит на нет — остаётся ровный белый шар
                hull(p.x, p.y, r, col, angle: o.ang, rust: 1 - on)
            }
            if !c.main { circle(p.x, p.y, r, col) }
            var starAngle: Float = 0
            if game.probesOn { starAngle = o.ang }                                   // лучи звезды смотрят вдоль щупов
            if game.byDirection {
                // по направлению звезда не вращается: её лучи смотрят туда же, куда стрелки кнопок, главный луч —
                // по стрелке средней кнопки; поворачивается только вместе со шкалой
                starAngle = game.arrowAngle(game.held.count / 2) + .pi / 2
            }
            if c.main {                                                                      // герб: красная звезда
                var emblem = K.COL_EMBLEM
                emblem.w = fade
                star(p.x, p.y, r * 0.4, inner: r * 0.17, emblem, angle: starAngle)
            }
            if c.main && game.probesOn && !game.byDirection {
                // нашлёпки на борту: по одной у основания каждого щупальца, вращаются вместе с кораблём;
                // из своей нашлёпки выходит волна выстрела. У включённого щупальца яркая, у выключенного тусклая.
                let bodies = game.bodies
                for s in 0..<game.held.count where s < game.nuclei.count {
                    let n = game.nuclei[s]
                    let d = rot(game.dx(bodies[n].pos.x, o.pos.x), game.dy(bodies[n].pos.y, o.pos.y))
                    let k = game.probeSector(s)
                    var red = K.COL_RIVET
                    // кусочек, торчащий за борт, — тот же красный, сильно разбавленный белым: на тёмном фоне его видно
                    var tip = red + (SIMD4<Float>(1, 1, 1, 1) - red) * 0.55
                    // размеры: полуширина 2.3, наружу торчит на 1.0, вглубь на 14% радиуса (у выключенной — на 10%)
                    var inner = r * 0.86
                    if k < game.probeOff.count && game.probeOff[k] { red.w = 0.45; tip.w = 0.45; inner = r * 0.90 }
                    red.w *= fade; tip.w *= fade
                    let a = atan2(d.y, d.x)
                    rimMark(p.x, p.y, inner: r - 0.5, outer: r + 1.0, angle: a, halfWidth: 2.3, tip)   // светлый, выглядывает наружу
                    rimMark(p.x, p.y, inner: inner, outer: r, angle: a, halfWidth: 2.3, red)            // красный, внутри борта
                }
            }
            if c.main && game.byDirection {
                // указатель: золотая метка на борту изнутри. Наружный край — дуга по радиусу корабля (торчит
                // на волосок), внутренний — дуга чуть меньшего круга, бока прямые, без скруглений.
                // Показывает то же направление, что риска на шкале, то есть куда кидает средняя кнопка.
                // Таких меток пять, по одной на направление каждой кнопки: средняя яркая, остальные приглушены.
                let mid = game.held.count / 2
                for k in 0..<game.held.count {
                    var gold = rgb("#ffd60a")
                    var inner = r * 0.905                       // главная метка
                    if k != mid { gold.w = 0.45; inner = r * 0.935 }   // остальные тусклее и чуть ниже
                    rimMark(p.x, p.y, inner: inner, outer: r + 0.5, angle: game.arrowAngle(k), halfWidth: 1.5, gold)
                }
            }
            if n > 0 {
                let er = max(1.2, r * 0.21)                   // 0.21 — размер электронов (меньше)
                for k in 0..<n {
                    let a = spin + Float(k) * (.pi * 2 / Float(n))
                    circle(p.x + cos(a) * orbitR, p.y + sin(a) * orbitR, er, SIMD4<Float>(1, 1, 1, 1))
                }
            }
            return
        }
        if o.cap > 0 {                                          // растворяется в поглотителе → белеет
            var col = K.COL_ATOM + (SIMD4<Float>(1, 1, 1, 1) - K.COL_ATOM) * o.cap; col.w = 1
            circle(p.x, p.y, r, col)
            return
        }
        let base = o.isMine ? K.COL_MINE : K.COL_ATOM
        let t = min(1, Float(o.nbr) / Float(game.explode.max))
        circle(p.x, p.y, r, mixCol(base, max(o.heat, t)))
    }

    // MARK: - кадр

    mutating func build() -> RenderScene {
        let cam = game.mainCore.pos
        let bodies = game.bodies

        // звёзды
        for s in game.stars {
            let so = rot(game.dx(s.x, cam.x) * scale, game.dy(s.y, cam.y) * scale)
            let sx = so.x, sy = so.y
            if sx < -cx || sx > cx || sy < -cy || sy > cy { continue }
            let r: Float = s.big ? 1.6 : 1.0
            circle(cx + sx, cy + sy, r, s.big ? K.COL_STAR_BRIGHT : K.COL_STAR)   // круглые, не квадратики
        }

        // радиус «магнита» вокруг ядер (при щупах его нет: захват идёт по длине щупа, не по радиусу)
        for c in 0..<game.cores.count where !game.probesOn {
            let p = screen(bodies[c].pos.x, bodies[c].pos.y, cam: cam)
            circle(p.x, p.y, K.LINK_R * scale, rgba(86, 224, 160, 0.10), inner: K.LINK_R * scale - 1)
        }

        // поглотитель
        let zone = game.zone
        let zp = screen(zone.x, zone.y, cam: cam)
        let zr = zone.r * scale
        let pulse = 0.5 + 0.5 * sin(game.gfxSpin * 0.4)
        // ярче и насыщеннее прежнего: на фактурном фоне бледное пятно терялось
        circle(zp.x, zp.y, zr * 1.2, rgba(190, 105, 255, 0.40 + 0.12 * pulse), soft: 1)      // свечение
        circle(zp.x, zp.y, zr * 0.6, rgba(232, 190, 255, 0.34 + 0.10 * pulse), soft: 1)      // светлая сердцевина
        for i in 0..<56 {
            let fi = Float(i)
            let sp = 0.25 + Float(i % 7) * 0.05, ph = fi * 1.7
            let dir: Float = i % 2 == 1 ? 1 : -1
            let ang = fi * 2.39996 + game.gfxSpin * sp * dir
            let rad = zr * (0.22 + 0.98 * (0.5 + 0.5 * sin(game.gfxSpin * (0.4 + Float(i % 5) * 0.16) + ph)))
            let tw = 0.5 + 0.5 * sin(game.gfxSpin * 1.3 + ph)
            let pr: Float = 1.4 + (i % 3 == 0 ? 2.0 : 0.8)
            circle(zp.x + cos(ang) * rad, zp.y + sin(ang) * rad, pr * scale, rgba(225, 190, 255, 0.25 + 0.50 * tw))
        }
        scene.zoneLabel = CGPoint(x: CGFloat(zp.x), y: CGFloat(zp.y - zr - 12))

        // порядок: якоря → свободные → свои → связи → ядра
        let n = game.count
        for i in 0..<n where bodies[i].type == BodyType.anchor { drawBody(i, cam: cam) }
        for i in 0..<n where bodies[i].type == BodyType.dust { drawBody(i, cam: cam) }
        for i in 0..<n where bodies[i].type == BodyType.atom && !bodies[i].isMine { drawBody(i, cam: cam) }
        for i in 0..<n where bodies[i].type == BodyType.atom && bodies[i].isMine { drawBody(i, cam: cam) }

        if game.showBonds {
            let col = rgba(180, 200, 255, 0.35)
            for a in 0..<game.cores.count {
                let ap = screen(bodies[a].pos.x, bodies[a].pos.y, cam: cam)
                for b in game.cores[a].bonds.keys {
                    let bo = rot(game.dx(bodies[b].pos.x, bodies[a].pos.x) * scale, game.dy(bodies[b].pos.y, bodies[a].pos.y) * scale)
                    let bx = ap.x + bo.x, by = ap.y + bo.y
                    line(ap.x, ap.y, bx, by, col)
                }
            }
        }

        buildProbes(cam: cam)

        for c in 0..<game.cores.count where !game.cores[c].main { drawBody(c, cam: cam) }
        for c in 0..<game.cores.count where game.cores[c].main { drawBody(c, cam: cam) }

        // «пук» энергии
        for p in game.puffs {
            let pp = screen(p.x, p.y, cam: cam)
            circle(pp.x, pp.y, (2 + 3 * (1 - p.life)) * scale, rgba(150, 220, 255, 0.5 * p.life))
        }

        // волны от выстрела: три тонкие концентрические дуги одна за другой расходятся из точки борта к щупальцу.
        // Передняя доходит до ядрышка ровно в момент, когда комок срывается; дуги идут дальше сквозь него и гаснут.
        if let pr = game.round.probes, !game.shotWaves.isEmpty {
            let host = bodies[0]
            let hp = screen(host.pos.x, host.pos.y, cam: cam)
            let dist = (pr.length - host.r) * scale                    // от борта до ядрышка
            for wv in game.shotWaves {
                // холостая волна (щупальце восстанавливается) — слабее и до ядрышка не достаёт
                let reach = dist * (wv.weak ? ShotWave.weakReach : ShotWave.overshoot)
                let strength: Float = wv.weak ? 0.8 : 0.9
                let o = rot(wv.out.x, wv.out.y)                        // направление на экране
                let ox = hp.x + o.x * host.r * scale, oy = hp.y + o.y * host.r * scale
                let ang = atan2(o.y, o.x)
                for k in 0..<3 {
                    let age = wv.t - Float(k) * ShotWave.lag
                    if age <= 0 { continue }
                    let rad = dist * age / ShotWave.delay
                    if rad >= reach { continue }
                    var col = rgba(207, 230, 255, strength * (1 - rad / reach))
                    if k > 0 { col.w *= 0.7 }
                    rimMark(ox, oy, inner: rad - 0.6, outer: rad + 0.6, angle: ang, halfWidth: rad * 0.62, col)
                }
            }
        }
        buildZoneArrow(zp: zp)
        buildMinimap(cam: cam)
        return scene
    }

    /// Щупы хоста: пять оттенков красного от светлого к тёмному, кнопка внизу того же оттенка.
    /// На конце каждого щупа постоянное ядрышко; зёрна комка, прицепившиеся к нему, залиты тем же оттенком.
    private mutating func buildProbes(cam: SIMD2<Float>) {
        if !game.probesOn { return }
        let bodies = game.bodies
        let host = bodies[0]
        let hp = screen(host.pos.x, host.pos.y, cam: cam)
        guard let pr = game.round.probes else { return }
        let fade = game.shipFade
        if fade <= 0 { return }
        for s in 0..<game.held.count {
            guard s < game.nuclei.count else { continue }
            let k = game.probeSector(s)                  // цвет, кнопка и «выключено» — по сектору, где щуп сейчас
            // цвет перетекает плавно: между центрами соседних секторов — смесь двух оттенков
            let blend = game.probeSectorBlend(s)
            let colFrom = K.PROBE_COLORS[(blend.from + pr.colorOffset) % K.PROBE_COLORS.count]
            var col = colFrom + (K.PROBE_COLORS[(blend.to + pr.colorOffset) % K.PROBE_COLORS.count] - colFrom) * blend.t
            col.w = fade                                   // щупальца тают вместе с кораблём
            for j in game.held[s] {
                let ao = rot(game.dx(bodies[j].pos.x, host.pos.x) * scale, game.dy(bodies[j].pos.y, host.pos.y) * scale)
                let ax = hp.x + ao.x, ay = hp.y + ao.y
                circle(ax, ay, bodies[j].r * scale + 0.4, col)
            }
            let n = game.nuclei[s]
            let to = rot(game.dx(bodies[n].pos.x, host.pos.x) * scale, game.dy(bodies[n].pos.y, host.pos.y) * scale)
            let tx = hp.x + to.x, ty = hp.y + to.y
            let nr = bodies[n].r * scale
            // долгое нажатие на кнопку. Выключение: кольцо стягивается к ядрышку и ярчает; сомкнулось — щуп
            // выключен. Включение — то же самое, прокрученное задом наперёд: ядрышко сразу целое, кольцо
            // стартует вплотную к нему, расходится с той же скоростью и тускнеет до исходной яркости.
            let hold = game.probeHoldProgress(k)
            let isOff = k < game.probeOff.count && game.probeOff[k]
            if hold > 0 {
                let closing = isOff ? 1 - hold : hold           // 1 — кольцо у самого ядрышка
                var ring = col
                ring.w = (0.35 + 0.6 * closing) * fade
                let rr = nr + 1.5 + 9 * (1 - closing)
                circle(tx, ty, rr, ring, inner: rr - 1.4)
            }
            // выключенный щуп: ядрышко едва заметным пустым колечком (пока его не начали включать).
            // По направлению ловят все щупы, выключается только стрельба в сторону — ядрышко видно всегда.
            if isOff && hold <= 0 && !game.byDirection {
                var faint = col
                faint.w = 0.25 * fade
                circle(tx, ty, nr, faint, inner: nr - 1)
                continue
            }
            if isOff && !game.byDirection {
                circle(tx, ty, nr, col)
                continue
            }
            // после выстрела ядрышко улетело: новое нарастает на конце щупа за время перезарядки
            var reload: Float = 0
            if s < game.probeReload.count, pr.reload > 0 { reload = game.probeReload[s] / pr.reload }
            if game.controlsLocked { continue }             // кнопки ещё не выданы — камня на щупальце нет вовсе
            circle(tx, ty, max(0.4, nr * (1 - reload)), col)
        }
    }

    /// Компас у корабля: стрелка на кольце вокруг хоста всегда смотрит точно на поглотитель
    /// и плавно гаснет при подлёте к нему. Никаких сдвигов — направление всегда честное.
    private mutating func buildZoneArrow(zp: SIMD2<Float>) {
        let d = zp - SIMD2<Float>(cx, cy)
        let len = simd_length(d)
        if len < 1 { return }
        let dir = d / len
        // гаснет, когда поглотитель рядом: полностью видна дальше ~350 единиц, пропадает ближе ~190
        let zr = game.zone.r * scale
        let fade = min(1, max(0, (len - (zr + 60 * scale)) / (160 * scale)))
        if fade <= 0 { return }
        let ringR: Float = 70 * scale                                       // чуть дальше от корабля
        let center = SIMD2<Float>(cx, cy) + dir * ringR
        let pulse = 0.25 + 0.75 * (0.5 + 0.5 * sin(game.gfxSpin * 1.2))   // мигание по прозрачности
        let ang = atan2(dir.y, dir.x)
        let halfW: Float = 20, height: Float = 9                            // плоский клин: тупой угол при острие (~118°)
        var ship = rgb("#be78ff")                                           // цвет поглотителя: стрелка указывает на него
        ship.w = 0.22 * pulse * fade
        circle(center.x, center.y, halfW * 1.5, ship, soft: 1)             // свечение
        ship.w = 0.95 * pulse * fade
        arrow(center.x, center.y, halfWidth: halfW, height: height, angle: ang, ringR: ringR, ship)
        if game.chalkT >= 0 { chalkOutline(center: center, dir: dir, halfW: halfW, height: height, t: game.chalkT) }
    }

    /// Стрелку обводят белым «мелом»: треугольник вокруг клина рисуется тремя штрихами (чик-чик-чик),
    /// пропадает и рисуется второй раз, чуть по-другому, потом гаснет. Штрих — цепочка мелких точек
    /// с неровной яркостью, концы перехлёстывают углы, как от руки. Обводка едет вместе со стрелкой.
    private mutating func chalkOutline(center: SIMD2<Float>, dir: SIMD2<Float>, halfW: Float, height: Float, t: Float) {
        let perp = SIMD2<Float>(-dir.y, dir.x)
        // вершины в осях клина (x — наружу от корабля): два угла основания и острие, с запасом вокруг клина
        let a = SIMD2<Float>(-11, -(halfW + 13)), b = SIMD2<Float>(height + 13, 0), c = SIMD2<Float>(-11, halfW + 13)
        let sides = [(a, b), (b, c), (c, a)]
        let stroke: Float = 0.10, gap: Float = 0.03
        // два прохода: когда начинается, до какого момента виден целиком, за сколько гаснет
        let passes: [(start: Float, hold: Float, fade: Float)] = [(0, 0.60, 0.15), (0.80, 1.90, 0.40)]
        for (pi, pass) in passes.enumerated() {
            let lt = t - pass.start
            if lt < 0 { continue }
            var alpha: Float = 1
            if t > pass.hold { alpha = 1 - (t - pass.hold) / pass.fade }
            if alpha <= 0 { continue }
            for (si, side) in sides.enumerated() {
                let progress = min(1, (lt - Float(si) * (stroke + gap)) / stroke)
                if progress <= 0 { continue }
                // рука неточна: концы штриха сдвинуты, у каждого прохода по-своему
                let seed = Float(pi * 3 + si)
                let j0 = SIMD2<Float>(sin(seed * 12.9) * 2.2, cos(seed * 7.3) * 2.2)
                let j1 = SIMD2<Float>(cos(seed * 5.1) * 2.2, sin(seed * 9.7) * 2.2)
                let from = side.0 + j0, to = side.1 + j1
                let d = to - from
                let len = simd_length(d)
                let u = d / len
                let over: Float = 3.5                              // перехлёст за углы
                let total = len + over * 2
                let n = Int(total * progress / 1.1)
                for k in 0...max(0, n) {
                    let along = -over + Float(k) * 1.1
                    let noise = sin(Float(k) * 3.7 + seed * 5) * 0.5 + sin(Float(k) * 1.3 + seed) * 0.5   // −1…1, не меняется от кадра к кадру
                    let lp = from + u * along + SIMD2<Float>(-u.y, u.x) * (noise * 0.45)
                    let sp = center + dir * lp.x + perp * lp.y
                    circle(sp.x, sp.y, 0.95 + 0.25 * noise, SIMD4<Float>(1, 1, 1, (0.72 + 0.25 * noise) * alpha))
                }
            }
        }
    }

    /// Где стоит миникарта. Широкий экран — вверху справа, как в прототипе. Телефон: с HUD — внизу
    /// справа (HUD занимает верх), без HUD — вверху справа под вырезом (низ отдан кнопкам).
    private func minimapRect() -> (x: Float, y: Float, s: Float) {
        let phone = w < 500
        let s: Float = phone ? 110 : 180
        let x = w - s - 12
        if !phone { return (x, 12, s) }
        if game.round.controls.hud { return (x, h - s - 34, s) }
        return (x, 62, s)
    }

    private mutating func buildMinimap(cam: SIMD2<Float>) {
        let bodies = game.bodies
        let mm = minimapRect()
        let mmS = mm.s, mmX = mm.x, mmY = mm.y
        let mmc = mmX + mmS / 2, mmm = mmY + mmS / 2
        let sc = mmS / K.WORLD_W
        rect(mmX, mmY, mmS, mmS, rgba(5, 8, 14, 0.45))
        let border = rgba(120, 150, 200, 0.16)           // тонкая неяркая обводка
        line(mmX, mmY, mmX + mmS, mmY, border)
        line(mmX + mmS, mmY, mmX + mmS, mmY + mmS, border)
        line(mmX + mmS, mmY + mmS, mmX, mmY + mmS, border)
        line(mmX, mmY + mmS, mmX, mmY, border)

        let zone = game.zone
        let zr = max(3, zone.r * sc)
        // миникарта повёрнута вместе с видом: направление на поглотитель на ней то же, что на экране
        let zo = rot(game.dx(zone.x, cam.x) * sc, game.dy(zone.y, cam.y) * sc)
        circle(mmc + zo.x, mmm + zo.y, zr, rgba(190, 140, 255, 0.85), inner: zr - 1)

        for o in 0..<game.count where bodies[o].type == BodyType.atom {
            let col = bodies[o].isMine ? K.COL_MINE : rgba(138, 160, 189, 0.45)
            let mo = rot(game.dx(bodies[o].pos.x, cam.x) * sc, game.dy(bodies[o].pos.y, cam.y) * sc)
            if abs(mo.x) > mmS / 2 || abs(mo.y) > mmS / 2 { continue }
            rect(mmc + mo.x - 0.7, mmm + mo.y - 0.7, 1.4, 1.4, col)
        }
        for c in 0..<game.cores.count where !game.cores[c].main {
            let co = rot(game.dx(bodies[c].pos.x, cam.x) * sc, game.dy(bodies[c].pos.y, cam.y) * sc)
            if abs(co.x) > mmS / 2 || abs(co.y) > mmS / 2 { continue }
            let px = mmc + co.x, py = mmm + co.y
            circle(px, py, 2.2, game.cores[c].col)
        }
        // корабль в центре: кружок цвета корпуса без обводки, внутри звёздочка герба
        circle(mmc, mmm, 5, game.hullColor)
        star(mmc, mmm, 3.6, inner: 1.5, K.COL_EMBLEM)
    }
}
