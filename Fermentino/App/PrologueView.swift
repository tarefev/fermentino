//
//  PrologueView.swift
//  Fermentino
//
//  Предыстория: три кадра с репликами профессора, тап листает, назад нельзя,
//  затем чёрный экран с девизом и старт первого тура.
//

import SwiftUI

private let prologueText = Color(red: 0xcf / 255, green: 0xe6 / 255, blue: 1)
private let prologueLine = Color(red: 0xf4 / 255, green: 0xec / 255, blue: 0xdc / 255)   // реплики на кадрах: тёплый белый, под бумагу

struct PrologueView: View {
    let onFinish: () -> Void
    @State private var index = 0

    // anchor и shift — как картинка обрезается по ширине экрана (она шире него): у каждого кадра своё
    private let frames: [(image: String?, key: String, anchor: Alignment, shift: CGFloat)] = [
        ("prologue1", "prologue.1", .leading, -18),   // слева остаются профессор и его рука целиком
        ("prologue2", "prologue.2", .center, 0),      // по центру: справа виден ассистент у чертежа
        ("prologue3", "prologue.3", .leading, -18),
        (nil, "prologue.tagline", .center, 0),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            let frame = frames[index]
            if let name = frame.image, let ui = UIImage(named: name) {
                // картинка заполняет экран как фон и обрезается по нему: сама по себе она шире экрана,
                // и без этого растягивала всю разметку — реплика уезжала под края
                Color.clear
                    .overlay(alignment: frame.anchor) { Image(uiImage: ui).resizable().scaledToFill().offset(x: frame.shift) }
                    .clipped()
                    .ignoresSafeArea()
            }
            VStack {
                if frame.image != nil {
                    // реплика внизу кадра: наверху она закрывала лицо профессора
                    Spacer()
                    Text(Strings.t(frame.key))
                        // Russo One: широкий рубленый шрифт советского плакатного склада, с кириллицей
                        .font(.custom("RussoOne-Regular", size: 16))
                        .foregroundStyle(prologueLine)
                        .multilineTextAlignment(.leading)   // прижат к левому краю, не по центру
                        .lineSpacing(9)
                        .shadow(color: .black, radius: 8, y: 2)
                        .padding(.horizontal, 36)          // поля по бокам: строки не упираются в края экрана
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.62))
                        .padding(.bottom, 64)              // вся плашка поднята от нижнего края
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
