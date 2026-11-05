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

    init(game: Game, size: CGSize, scale: Float) {
        self.game = game
        self.w = Float(size.width)
        self.h = Float(size.height)
        self.scale = scale
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

    private mutating func star(_ x: Float, _ y: Float, _ outer: Float, inner: Float, _ color: SIMD4<Float>, angle: Float = 0) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.halfSize = SIMD2<Float>(angle, 0)   // для звезды: угол поворота
        s.radius = outer
        s.inner = inner / outer      // для звезды: отношение внутреннего радиуса к внешнему
        s.color = color
        s.shape = 2
        scene.shapes.append(s)
    }

    private mutating func arrow(_ x: Float, _ y: Float, _ size: Float, angle: Float, _ color: SIMD4<Float>) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.radius = size
        s.halfSize = SIMD2<Float>(angle, 0)   // для стрелки: угол поворота
        s.color = color
        s.shape = 3
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
        let ox = game.dx(x, cam.x) * scale, oy = game.dy(y, cam.y) * scale
        return SIMD2<Float>(cx + ox, cy + oy)
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
            if o.cap > 0 { col = col + (SIMD4<Float>(1, 1, 1, 1) - col) * o.cap; col.w = 1 }
            let spin = game.gfxSpin * 0.8 + c.spinPhase      // 0.8 — скорость вращения электронов
            let orbitR = r * 0.7                               // 0.7 — радиус орбиты (ближе к краю)
            var n = max(0, c.valence - c.bonds.count)
            if c.main && game.probesOn { n = 0 }           // у хоста свободные щупы рисуются штырями, не электронами
            let blur: Float = c.main ? 14 : 10
            var glow = col; glow.w = 0.55
            circle(p.x, p.y, r + blur * scale, glow, soft: 1)
            circle(p.x, p.y, r, col)
            var starAngle: Float = 0
            if game.probesOn { starAngle = o.ang }                                   // лучи звезды смотрят вдоль щупов
            if c.main { star(p.x, p.y, r * 0.4, inner: r * 0.17, rgb("#ffd60a"), angle: starAngle) }   // герб: золотая звезда
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
            let sx = game.dx(s.x, cam.x) * scale, sy = game.dy(s.y, cam.y) * scale
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
                    let bx = ap.x + game.dx(bodies[b].pos.x, bodies[a].pos.x) * scale
                    let by = ap.y + game.dy(bodies[b].pos.y, bodies[a].pos.y) * scale
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

        buildZoneArrow(zp: zp)
        buildMinimap(cam: cam)
        return scene
    }

    /// Щупы хоста без линий: пойманное тело залито цветом щупа; у свободного — точка на месте конца щупа.
    /// Цвет щупа совпадает с цветом его кнопки внизу экрана.
    private mutating func buildProbes(cam: SIMD2<Float>) {
        if !game.probesOn { return }
        let bodies = game.bodies
        let host = bodies[0]
        let hp = screen(host.pos.x, host.pos.y, cam: cam)
        let slots = game.cores[0].slots
        for s in 0..<game.holds.count {
            var col = K.PROBE_COLORS[s % K.PROBE_COLORS.count]
            let j = game.holds[s]
            if j >= 0 {
                let ax = hp.x + game.dx(bodies[j].pos.x, host.pos.x) * scale
                let ay = hp.y + game.dy(bodies[j].pos.y, host.pos.y) * scale
                col.w = 1
                circle(ax, ay, bodies[j].r * scale, col)      // пойманный шар целиком в цвете своего щупа
                continue
            }
            guard s < slots.count else { continue }
            let a = host.ang + slots[s]
            var bump: Float = 0
            if s < game.probePulse.count { bump = sin(game.probePulse[s] * .pi) }
            var r1 = host.r * scale + 12
            if let pr = game.round.probes { r1 = pr.length * scale }   // там же, где встанет центр пойманного тела
            // перезарядка после выстрела: вместо точки тусклое кольцо, которое стягивается к точке
            var reload: Float = 0
            if s < game.probeReload.count, let pr = game.round.probes, pr.reload > 0 { reload = game.probeReload[s] / pr.reload }
            if reload > 0 {
                col.w = 0.45
                let rr = 2.5 + 6 * reload
                circle(hp.x + cos(a) * r1, hp.y + sin(a) * r1, rr, col, inner: rr - 1.2)
                continue
            }
            col.w = 0.6 + 0.3 * bump
            // рывок = шарик на месте чуть вырос и вернулся, без вылета наружу
            circle(hp.x + cos(a) * r1, hp.y + sin(a) * r1, 2 + 1.3 * bump, col)
        }
    }

    /// Стрелка на краю экрана в сторону поглотителя (если он не виден).
    private mutating func buildZoneArrow(zp: SIMD2<Float>) {
        let margin: Float = 36
        let inside = zp.x > margin && zp.x < w - margin && zp.y > margin + 150 && zp.y < h - margin
        if inside { return }
        let d = zp - SIMD2<Float>(cx, cy)
        let len = simd_length(d)
        if len < 1 { return }
        let dir = d / len
        // точка на прямоугольнике отступа, по лучу из центра
        let halfW = cx - margin, halfH = cy - margin
        var t = Float.infinity
        if abs(dir.x) > 1e-4 { t = min(t, halfW / abs(dir.x)) }
        if abs(dir.y) > 1e-4 { t = min(t, halfH / abs(dir.y)) }
        var tip = SIMD2<Float>(cx, cy) + dir * t
        // не залезать на миникарту
        let mm = minimapRect()
        if tip.x > mm.x - 18 && tip.x < mm.x + mm.s + 18 && tip.y > mm.y - 18 && tip.y < mm.y + mm.s + 18 {
            if mm.y < h / 2 { tip.y = mm.y + mm.s + 18 } else { tip.y = mm.y - 18 }
        }
        // и на ряд кнопок щупов внизу
        if game.probesOn && tip.y > h - 150 { tip.y = h - 150 }
        let pulse = 0.25 + 0.75 * (0.5 + 0.5 * sin(game.gfxSpin * 1.2))   // мигание по прозрачности
        let ang = atan2(dir.y, dir.x)
        let size: Float = 19            // крупнее, яркость та же
        let center = tip - dir * (size * 0.3)
        var ship = rgb("#cc1414")                                           // цвет корабля
        ship.w = 0.25 * pulse
        circle(center.x, center.y, size * 2.2, ship, soft: 1)              // свечение
        ship.w = 0.95 * pulse
        arrow(center.x, center.y, size, angle: ang, ship)
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
        circle(mmc + game.dx(zone.x, cam.x) * sc, mmm + game.dy(zone.y, cam.y) * sc, zr, rgba(190, 140, 255, 0.85), inner: zr - 1)

        for o in 0..<game.count where bodies[o].type == BodyType.atom {
            let col = bodies[o].isMine ? K.COL_MINE : rgba(138, 160, 189, 0.45)
            rect(mmc + game.dx(bodies[o].pos.x, cam.x) * sc - 0.7, mmm + game.dy(bodies[o].pos.y, cam.y) * sc - 0.7, 1.4, 1.4, col)
        }
        for c in 0..<game.cores.count where !game.cores[c].main {
            let px = mmc + game.dx(bodies[c].pos.x, cam.x) * sc, py = mmm + game.dy(bodies[c].pos.y, cam.y) * sc
            circle(px, py, 2.2, game.cores[c].col)
        }
        // корабль в центре: красный кружок без обводки, внутри золотая звёздочка
        circle(mmc, mmm, 5, game.cores[0].col)
        star(mmc, mmm, 3.6, inner: 1.5, rgb("#ffd60a"))
    }
}
