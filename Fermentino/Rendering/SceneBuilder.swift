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

    private mutating func star(_ x: Float, _ y: Float, _ outer: Float, inner: Float, _ color: SIMD4<Float>) {
        var s = ShapeInstance()
        s.center = SIMD2<Float>(x, y)
        s.radius = outer
        s.inner = inner / outer      // для звезды: отношение внутреннего радиуса к внешнему
        s.color = color
        s.shape = 2
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
            let n = max(0, c.valence - c.bonds.count)
            let blur: Float = c.main ? 14 : 10
            var glow = col; glow.w = 0.55
            circle(p.x, p.y, r + blur * scale, glow, soft: 1)
            circle(p.x, p.y, r, col)
            if c.main { star(p.x, p.y, r * 0.4, inner: r * 0.17, rgb("#ffd60a")) }   // герб: золотая звезда
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
            rect(cx + sx - r, cy + sy - r, r * 2, r * 2, s.big ? K.COL_STAR_BRIGHT : K.COL_STAR)
        }

        // радиус «магнита» вокруг ядер
        for c in 0..<game.cores.count {
            let p = screen(bodies[c].pos.x, bodies[c].pos.y, cam: cam)
            circle(p.x, p.y, K.LINK_R * scale, rgba(86, 224, 160, 0.10), inner: K.LINK_R * scale - 1)
        }

        // поглотитель
        let zone = game.zone
        let zp = screen(zone.x, zone.y, cam: cam)
        let zr = zone.r * scale
        let pulse = 0.5 + 0.5 * sin(game.gfxSpin * 0.4)
        circle(zp.x, zp.y, zr, rgba(175, 115, 255, 0.16 + 0.08 * pulse), soft: 1)
        for i in 0..<56 {
            let fi = Float(i)
            let sp = 0.25 + Float(i % 7) * 0.05, ph = fi * 1.7
            let dir: Float = i % 2 == 1 ? 1 : -1
            let ang = fi * 2.39996 + game.gfxSpin * sp * dir
            let rad = zr * (0.22 + 0.98 * (0.5 + 0.5 * sin(game.gfxSpin * (0.4 + Float(i % 5) * 0.16) + ph)))
            let tw = 0.5 + 0.5 * sin(game.gfxSpin * 1.3 + ph)
            let pr: Float = 1.1 + (i % 3 == 0 ? 1.8 : 0.6)
            circle(zp.x + cos(ang) * rad, zp.y + sin(ang) * rad, pr * scale, rgba(205, 170, 255, 0.06 + 0.20 * tw))
        }
        scene.zoneLabel = CGPoint(x: CGFloat(zp.x), y: CGFloat(zp.y - zr - 12))

        // порядок: якоря → свободные → свои → связи → ядра
        let n = game.count
        for i in 0..<n where bodies[i].type == BodyType.anchor { drawBody(i, cam: cam) }
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

    /// Стрелка на краю экрана в сторону поглотителя (если он не виден).
    private mutating func buildZoneArrow(zp: SIMD2<Float>) {
        let margin: Float = 28
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
        let tip = SIMD2<Float>(cx, cy) + dir * t
        let pulse = 0.6 + 0.4 * (0.5 + 0.5 * sin(game.gfxSpin * 1.2))
        let col = rgba(190, 140, 255, 0.9 * pulse)
        let size: Float = 14
        let side = SIMD2<Float>(-dir.y, dir.x)
        let base = tip - dir * size
        let l = base + side * (size * 0.55), r = base - side * (size * 0.55)
        line(tip.x, tip.y, l.x, l.y, col)
        line(tip.x, tip.y, r.x, r.y, col)
        line(l.x, l.y, r.x, r.y, col)
        let shaft = base - dir * (size * 0.6)
        line(base.x, base.y, shaft.x, shaft.y, col)
    }

    private mutating func buildMinimap(cam: SIMD2<Float>) {
        let bodies = game.bodies
        // на телефоне миникарта внизу справа, чтобы не перекрывать HUD; на широком экране — как в прототипе
        let phone = w < 500
        let mmS: Float = phone ? 120 : 180
        let mmX = w - mmS - 12
        let mmY: Float = phone ? h - mmS - 34 : 12
        let mmc = mmX + mmS / 2, mmm = mmY + mmS / 2
        let sc = mmS / K.WORLD_W
        rect(mmX, mmY, mmS, mmS, rgba(5, 8, 14, 0.45))   // без обрамления: только лёгкое затемнение

        let zone = game.zone
        let zr = max(3, zone.r * sc)
        circle(mmc + game.dx(zone.x, cam.x) * sc, mmm + game.dy(zone.y, cam.y) * sc, zr, rgba(190, 140, 255, 0.85), inner: zr - 1)

        for o in 0..<game.count where bodies[o].type == BodyType.atom {
            let col = bodies[o].isMine ? K.COL_MINE : rgba(138, 160, 189, 0.45)
            rect(mmc + game.dx(bodies[o].pos.x, cam.x) * sc - 0.7, mmm + game.dy(bodies[o].pos.y, cam.y) * sc - 0.7, 1.4, 1.4, col)
        }
        for c in 0..<game.cores.count {
            let px = mmc + game.dx(bodies[c].pos.x, cam.x) * sc, py = mmm + game.dy(bodies[c].pos.y, cam.y) * sc
            circle(px, py, game.cores[c].main ? 3 : 2.2, game.cores[c].col)
        }
        circle(mmc, mmm, 4, SIMD4<Float>(1, 1, 1, 1), inner: 3)
    }
}
