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

    func attach(_ view: MTKView) {
        guard renderer == nil else { return }
        renderer = Renderer(view: view, hud: hud)
        view.delegate = renderer
    }

    func press(_ key: HudKey) {
        renderer?.game.press(key)
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
        return view
    }

    func updateUIView(_ uiView: TouchMTKView, context: Context) {}
}

final class TouchMTKView: MTKView {
    var onTap: ((CGPoint, CGSize) -> Void)?
    var onLongPress: (() -> Void)?
    private var longPressTimer: Timer?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTap?(t.location(in: self), bounds.size)
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.onLongPress?()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
}
