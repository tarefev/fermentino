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

    func attach(_ view: MTKView) {
        guard renderer == nil else { return }
        renderer = Renderer(view: view, hud: hud)
        view.delegate = renderer
    }

    func press(_ key: HudKey) {
        renderer?.game.press(key)
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
        return view
    }

    func updateUIView(_ uiView: TouchMTKView, context: Context) {}
}

final class TouchMTKView: MTKView {
    var onTap: ((CGPoint, CGSize) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTap?(t.location(in: self), bounds.size)
    }
}
