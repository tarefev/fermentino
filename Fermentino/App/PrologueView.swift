//
//  PrologueView.swift
//  Fermentino
//
//  Предыстория: три кадра с репликами профессора, тап листает, назад нельзя,
//  затем чёрный экран с девизом и старт первого тура.
//

import SwiftUI

private let prologueLine = Color(red: 0xf4 / 255, green: 0xec / 255, blue: 0xdc / 255)   // реплики на кадрах: тёплый белый, под бумагу

struct PrologueView: View {
    let onFinish: () -> Void
    @State private var index = 0

    // anchor и shift — как картинка обрезается по ширине экрана (она шире него): у каждого кадра своё
    private let frames: [(image: String?, key: String, anchor: Alignment, shift: CGFloat)] = [
        ("prologue1", "prologue.1", .leading, -18),   // слева остаются профессор и его рука целиком
        ("prologue2", "prologue.2", .center, 0),      // по центру: справа виден ассистент у чертежа
        ("prologue3", "prologue.3", .leading, -30),   // капсула слева почти целиком, справа виден огонёк поглотителя
        (nil, "prologue.tagline", .center, 0),
    ]

    /// Текст реплики, раскрашенный по ходу записи `voice`: сказанные слова — полным цветом, остальные бледные.
    /// Нет записи, нет расписания или число слов не сошлось — весь текст полным цветом.
    private func karaoke(_ text: String, voice: String) -> AttributedString {
        var out = AttributedString()
        // слова разделены пробелом или неразрывным пробелом (им приклеены короткие слова, см. Strings.glue)
        var words: [(word: String, sep: String)] = []
        var cur = ""
        for ch in text {
            if ch == " " || ch == "\u{00A0}" { words.append((cur, String(ch))); cur = ""; continue }
            cur.append(ch)
        }
        if !cur.isEmpty { words.append((cur, "")) }
        let times = VoiceTimings.words[voice]
        let now = Voice.shared.time(of: voice)
        for (i, w) in words.enumerated() {
            var piece = AttributedString(w.word + w.sep)
            var lit = true
            if let times, let now, times.count == words.count, now + 0.06 < times[i] { lit = false }
            piece.foregroundColor = lit ? prologueLine : prologueLine.opacity(0.26)
            out += piece
        }
        return out
    }

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
                    // караоке: слова загораются по ходу озвучки. Реплика стоит на плашке целиком с самого начала
                    // (несказанные слова бледные), поэтому строки не прыгают
                    TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                        Text(karaoke(Strings.t(frame.key), voice: "voice_prologue\(index + 1)"))
                    }
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
                    // девиз: тот же Russo One и тот же тёплый белый, что у реплик на кадрах, но крупнее и по центру
                    Text(Strings.t(frame.key))
                        .font(.custom("RussoOne-Regular", size: 22))
                        .foregroundStyle(prologueLine)
                        .multilineTextAlignment(.center)
                        .lineSpacing(16)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)           // длинная строка ужимается, а не переносится
                        .padding(.horizontal, 24)
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
        // озвучка кадра: файл voice_prologueN.m4a, если он записан; смена кадра обрывает реплику.
        // Кадр без записи ждёт тапа, как раньше.
        .onChange(of: index, initial: true) { _, now in
            // реплика доиграла — кадр перелистывается сам, после короткой паузы; тап по-прежнему листает сразу
            Voice.shared.play("voice_prologue\(now + 1)", delay: 0.4) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if index == now && index + 1 < frames.count { index += 1 }
                }
            }
        }
        .onDisappear { Voice.shared.stop() }
        .task(id: index) {
            // девиз тапа не ждёт: повисел K.TAGLINE_HOLD секунд и сам начинает растворяться (тап ускоряет)
            if frames[index].image != nil { return }
            try? await Task.sleep(nanoseconds: UInt64(K.TAGLINE_HOLD * 1_000_000_000))
            if Task.isCancelled { return }
            onFinish()
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
