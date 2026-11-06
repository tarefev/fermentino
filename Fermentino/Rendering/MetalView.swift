//
//  MetalView.swift
//  Fermentino
//
//  SwiftUI-обёртка над MTKView: тап = выстрел в точку (как клик мышью в прототипе).
//

import SwiftUI
import MetalKit

/// Связка игры и рендерера, живёт на уровне ContentView; HUD-кнопки ходят через неё.
final class GameSession {
    let hud = HUDModel()
    private(set) var renderer: Renderer?
    var onRestartToStory: (() -> Void)?

    /// Пока true, тур не начинает свой отсчёт: корабль стоит ржавым, реплик нет (игра лежит под девизом).
    var holdIntro = false { didSet { renderer?.game.introHold = holdIntro } }

    func attach(_ view: MTKView) {
        guard renderer == nil else { return }
        renderer = Renderer(view: view, hud: hud)
        renderer?.game.introHold = holdIntro
        view.delegate = renderer
    }

    func press(_ key: HudKey) {
        renderer?.game.press(key)
    }

    func throwProbe(_ s: Int) {
        renderer?.game.throwProbe(s)
    }

    func pressBegan(_ s: Int) {
        renderer?.game.pressBegan(s)
    }

    /// Ползунок над кнопками: поворот звезды секторов, градусы.
    func setStarTurn(degrees: Double) {
        Game.starTurn = Float(degrees * .pi / 180)
    }

    func pressEnded(_ s: Int) {
        renderer?.game.pressEnded(s)
    }

    func undoLast() {
        renderer?.game.undoLast()
    }

    func toggleControlMode() {
        guard let g = renderer?.game else { return }
        g.controlMode = g.controlMode == .buttons ? .swipe : .buttons
    }

    /// Свайп в точках экрана и его скорость (pt/с): вариант Б — бросок по направлению свайпа.
    func swipe(dx: CGFloat, dy: CGFloat, speed: CGFloat) {
        guard let g = renderer?.game, g.controlMode == .swipe else { return }
        let strength = Float(min(1.8, max(0.4, speed / 1200)))
        g.throwInDirection(Float(dx), Float(dy), strength: strength)
    }

    /// Тест: вернуться к самому началу истории — пролог, затем тур 1 с нуля.
    func restartToStory() {
        Progress.roundIndex = 0
        Progress.prologueSeen = false
        renderer = nil                 // игра и GPU-буферы создадутся заново после пролога
        onRestartToStory?()
    }
}

struct MetalView: UIViewRepresentable {
    let session: GameSession

    func makeUIView(context: Context) -> TouchMTKView {
        let view = TouchMTKView(frame: .zero)
        view.backgroundColor = .black        // до первого кадра экран чёрный, а не белый
        view.framebufferOnly = true
        view.isMultipleTouchEnabled = false
        session.attach(view)
        view.onTap = { [session] point, size in
            guard let r = session.renderer else { return }
            r.game.tap(at: point, viewSize: size, scale: r.scale)
        }
        view.onLongPress = { [session] in
            session.restartToStory()     // тест: долгое нажатие 2 с = к началу истории
        }
        view.onSwipe = { [session] dx, dy, speed in
            session.swipe(dx: dx, dy: dy, speed: speed)
        }
        return view
    }

    func updateUIView(_ uiView: TouchMTKView, context: Context) {}
}

final class TouchMTKView: MTKView {
    var onTap: ((CGPoint, CGSize) -> Void)?
    var onLongPress: (() -> Void)?
    var onSwipe: ((CGFloat, CGFloat, CGFloat) -> Void)?
    private var longPressTimer: Timer?
    private var startPoint = CGPoint.zero
    private var startTime: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        startPoint = t.location(in: self)
        startTime = t.timestamp
        onTap?(startPoint, bounds.size)
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.onLongPress?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if hypot(p.x - startPoint.x, p.y - startPoint.y) > 10 { cancelLongPress() }   // палец поехал — это не удержание
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let dx = p.x - startPoint.x, dy = p.y - startPoint.y
        let dist = hypot(dx, dy)
        let dt = max(0.016, t.timestamp - startTime)
        if dist >= 24 && dt <= 0.7 { onSwipe?(dx, dy, dist / CGFloat(dt)) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }

    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
}
