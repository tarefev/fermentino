//
//  PrologueView.swift
//  Fermentino
//
//  Предыстория: три кадра с репликами профессора, тап листает, назад нельзя,
//  затем чёрный экран с девизом и старт первого тура.
//

import SwiftUI

private let prologueText = Color(red: 0xcf / 255, green: 0xe6 / 255, blue: 1)

struct PrologueView: View {
    let onFinish: () -> Void
    @State private var index = 0

    private let frames: [(image: String?, key: String)] = [
        ("prologue1", "prologue.1"),
        ("prologue2", "prologue.2"),
        ("prologue3", "prologue.3"),
        (nil, "prologue.tagline"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            let frame = frames[index]
            if let name = frame.image, let ui = UIImage(named: name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            VStack {
                if frame.image != nil {
                    Text(Strings.t(frame.key))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(prologueText)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black, radius: 8, y: 2)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.45))
                        .padding(.top, 8)
                    Spacer()
                } else {
                    Spacer()
                    Text(Strings.t(frame.key))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(prologueText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if index + 1 < frames.count {
                index += 1
            } else {
                onFinish()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
