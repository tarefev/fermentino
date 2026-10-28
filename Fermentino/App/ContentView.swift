//
//  ContentView.swift
//  Fermentino
//

import SwiftUI

struct ContentView: View {
    @StateObject private var stats = RendererStats()
    @State private var resetToken = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalView(stats: stats, resetToken: resetToken)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Text("\(Int(stats.fps.rounded())) fps")
                Text("\(stats.bodyCount) bodies")
                Button("reset") { resetToken += 1 }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.4), in: Capsule())
            .padding()
        }
        .statusBarHidden(true)
    }
}

#Preview {
    ContentView()
}
