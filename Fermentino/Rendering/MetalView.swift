//
//  MetalView.swift
//  Fermentino
//
//  SwiftUI-обёртка над MTKView с обработкой касаний.
//

import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    @ObservedObject var stats: RendererStats
    var resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TouchMTKView {
        let view = TouchMTKView(frame: .zero)
        view.framebufferOnly = true
        view.isMultipleTouchEnabled = false
        guard let renderer = Renderer(view: view, stats: stats) else {
            assertionFailure("Metal недоступен")
            return view
        }
        context.coordinator.renderer = renderer
        context.coordinator.resetToken = resetToken
        view.delegate = renderer
        view.onTouch = { [weak renderer, weak view] point in
            guard let renderer, let view else { return }
            renderer.setAttractor(screenPoint: point, in: view)
        }
        return view
    }

    func updateUIView(_ uiView: TouchMTKView, context: Context) {
        guard context.coordinator.resetToken != resetToken else { return }
        context.coordinator.resetToken = resetToken
        context.coordinator.renderer?.reset()
    }

    final class Coordinator {
        var renderer: Renderer?
        var resetToken = 0
    }
}

final class TouchMTKView: MTKView {
    var onTouch: ((CGPoint?) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTouch?(t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTouch?(t.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouch?(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouch?(nil)
    }
}
