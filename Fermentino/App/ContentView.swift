//
//  ContentView.swift
//  Fermentino
//
//  Игровой экран: Metal-вью + SwiftUI-оверлеи (HUD, интро, победа, подпись зоны).
//

import SwiftUI

private let hudText = Color(red: 0xcf / 255, green: 0xe6 / 255, blue: 1)
private let hudBold = Color(red: 0x7d / 255, green: 0xf9 / 255, blue: 0xc5 / 255)
private let hudDim = Color(red: 0x6e / 255, green: 0x86 / 255, blue: 0xa8 / 255)
private let hudKey = Color(red: 0x9f / 255, green: 0xc7 / 255, blue: 1)
private let hudBlue = Color(red: 0x6a / 255, green: 0xb8 / 255, blue: 1)
private let capColor = Color(red: 0x16 / 255, green: 0xf0 / 255, blue: 0xe6 / 255)
private let hubColor = Color(red: 1, green: 0x2d / 255, blue: 0xb0 / 255)
private let winTitle = Color(red: 0xc9 / 255, green: 0xa4 / 255, blue: 1)
private let winButton = Color(red: 0xb9 / 255, green: 0x8b / 255, blue: 1)

struct ContentView: View {
    @State private var session = GameSession()
    @State private var showPrologue = !Progress.prologueSeen

    var body: some View {
        if showPrologue {
            PrologueView {
                Progress.prologueSeen = true
                showPrologue = false
            }
        } else {
            gameScreen
                .onAppear { session.onRestartToStory = { showPrologue = true } }
        }
    }

    private var gameScreen: some View {
        ZStack {
            MetalView(session: session)
                .ignoresSafeArea()
            ZoneLabel(hud: session.hud)
                .ignoresSafeArea()
            if session.hud.controls.hud {
                VStack(alignment: .leading, spacing: 0) {
                    HUDView(hud: session.hud, session: session)
                    Spacer()
                    HelpView()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            if session.hud.probesOn {
                ProbeControls(hud: session.hud, session: session)
            }
            IntroView(hud: session.hud)
            NarrationView(hud: session.hud)
            WinView(hud: session.hud, session: session)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - HUD (§7)

private struct HUDView: View {
    let hud: HUDModel
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            let c = hud.controls
            HStack(spacing: 0) {
                Text("Тесей").foregroundStyle(hudBold).bold()
                sep(); label("время "); value(hud.time)
                sep(); label("скорость "); value("\(hud.speed)")
                if c.molecule { sep(); label("связей "); value("\(hud.bonds)") }
            }
            if c.valence || c.mass {
                HStack(spacing: 0) {
                    if c.valence {
                        label("валентность "); value("\(hud.valence)"); label(" ")
                        key("A") { session.press(.valenceDown) }; label("/"); key("S") { session.press(.valenceUp) }
                    }
                    if c.valence && c.mass { sep() }
                    if c.mass {
                        label("масса "); value("\(hud.mass)"); label("/\(Int(K.MASS_MAX)) ")
                        key("E") { session.press(.massDown) }; label("/"); key("R") { session.press(.massUp) }
                    }
                }
            }
            if c.gravity {
                HStack(spacing: 0) {
                    label("гравитация: ")
                    Text(hud.gravName).foregroundStyle(hud.gravIsNorm ? hudBold : hudBlue)
                    label(" ")
                    key("Q") { session.press(.gravLeft) }; label("/"); key("W") { session.press(.gravRight) }
                }
            }
            HStack(spacing: 0) {
                label("инертонов "); value("\(hud.mine)")
                if c.molecule { sep(); label("верных сцеплений фермента "); value("\(hud.goodBonds)/\(K.N_CAP)") }
            }
            if c.molecule {
                HStack(spacing: 0) {
                    label("фермент: ")
                    molStatus
                }
            }
            if hud.showDebug {
                Text(hud.debugLine1).foregroundStyle(hudDim)
                Text(hud.debugLine2).foregroundStyle(hudDim)
            }
            HStack(spacing: 0) {
                if c.toggles {
                    key("L") { session.press(.toggleBonds) }; dim(" связи")
                    sep(); key("D") { session.press(.toggleDebug) }; dim(" отладка")
                    sep(); key("B") { session.press(.toggleEjectMode) }; dim(" выброс")
                    sep()
                }
                key("⌫") { session.press(.restart) }; dim(" рестарт")
            }
            .padding(.top, 3)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(hudText)
        .shadow(color: .black, radius: 1, y: 1)
    }

    @ViewBuilder private var molStatus: some View {
        switch hud.molStatus {
        case .assembled:
            Text("СОБРАН → в поглотитель").foregroundStyle(hudBold)
        case .haveAll:
            Text("все компоненты у тебя — собери фермент").foregroundStyle(Color(red: 1, green: 0xd2 / 255, blue: 0x4a / 255))
        case .notAssembled:
            Text("не собран").foregroundStyle(Color(red: 1, green: 0x96 / 255, blue: 0x78 / 255))
        }
    }

    private func label(_ s: String) -> Text { Text(s) }
    private func value(_ s: String) -> Text { Text(s).foregroundStyle(hudBold).bold() }
    private func dim(_ s: String) -> Text { Text(s).foregroundStyle(hudDim) }
    private func sep() -> Text { Text(" · ") }

    private func key(_ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s)
                .foregroundStyle(hudKey)
                .underline(true, pattern: .dot, color: hudKey.opacity(0.6))
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HelpView: View {
    var body: some View {
        HStack {
            Text("ТАП = выстрелить ближайшим к точке инертоном в её сторону")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(hudDim)
                .shadow(color: .black, radius: 1, y: 1)
                .frame(maxWidth: 220, alignment: .leading)
            Spacer()
        }
    }
}

// MARK: - Интро: что собрать и куда

private struct IntroView: View {
    let hud: HUDModel

    var body: some View {
        if hud.introOpacity > 0 {
            VStack(spacing: 6) {
                ForEach(Array(hud.introLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
                if hud.introIcon {
                    MoleculeIcon(kind: hud.winKind)
                        .frame(width: 120, height: 110)
                        .padding(.top, 8)
                }
            }
            .font(.system(size: 17, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundStyle(hudText)
            .shadow(color: .black, radius: 6, y: 2)
            .padding(.horizontal, 24)
            .opacity(hud.introOpacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -140)
            .allowsHitTesting(false)
        }
    }
}

private struct MoleculeIcon: View {
    let kind: WinKind

    var body: some View {
        Canvas { ctx, size in
            let px = size.width / 2, py = size.height / 2
            let lineColor = Color(red: 180 / 255, green: 200 / 255, blue: 1).opacity(0.5)
            if kind == .benzene {
                // КОЛЬЦО: 6 хабов + 6 наружных кэпов
                let R: CGFloat = 28
                let hubs: [CGPoint] = (0..<6).map { k in
                    let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / 3
                    return CGPoint(x: px + cos(a) * R, y: py + sin(a) * R)
                }
                for k in 0..<6 {
                    var path = Path()
                    path.move(to: hubs[k]); path.addLine(to: hubs[(k + 1) % 6])
                    ctx.stroke(path, with: .color(lineColor), lineWidth: 2)
                }
                for k in 0..<6 {
                    let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / 3
                    let e = CGPoint(x: px + cos(a) * (R + 15), y: py + sin(a) * (R + 15))
                    var path = Path()
                    path.move(to: hubs[k]); path.addLine(to: e)
                    ctx.stroke(path, with: .color(lineColor), lineWidth: 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: e.x - 5, y: e.y - 5, width: 10, height: 10)), with: .color(capColor))
                }
                for h in hubs {
                    ctx.fill(Path(ellipseIn: CGRect(x: h.x - 7, y: h.y - 7, width: 14, height: 14)), with: .color(hubColor))
                }
                return
            }
            let R: CGFloat = 32
            for k in 0..<3 {
                let ang = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 3
                let ex = px + cos(ang) * R, ey = py + sin(ang) * R
                var path = Path()
                path.move(to: CGPoint(x: px, y: py))
                path.addLine(to: CGPoint(x: ex, y: ey))
                ctx.stroke(path, with: .color(Color(red: 180 / 255, green: 200 / 255, blue: 1).opacity(0.5)), lineWidth: 2)
                let cap = Path(ellipseIn: CGRect(x: ex - 7, y: ey - 7, width: 14, height: 14))
                ctx.addFilter(.shadow(color: capColor, radius: 4))
                ctx.fill(cap, with: .color(capColor))
            }
            let hub = Path(ellipseIn: CGRect(x: px - 10, y: py - 10, width: 20, height: 20))
            ctx.addFilter(.shadow(color: hubColor, radius: 5))
            ctx.fill(hub, with: .color(hubColor))
        }
    }
}

// MARK: - Управление щупами (тест двух вариантов: А — кнопки, Б — свайп)

/// Прицельная шкала над кнопками, как в бинокле: лента рисок едет под пальцем, посередине неподвижная
/// жирная риска. Тянешь — поворачивается звезда секторов (все стрелки разом). Круг замкнут, краёв нет.
/// Сама шкала узкая и прижата к низу, но тянуть можно по всей высоте вида (нижняя треть экрана).
private struct AimTape: View {
    @Binding var turn: Double                 // градусы, −180…180
    let onChange: (Double) -> Void
    @State private var dragStart: Double? = nil
    private let ptPerDeg: CGFloat = 2         // на экране видно около 150° шкалы
    private let stepDeg = 6.0                 // малая риска; каждая пятая (30°) — большая
    private let inset: CGFloat = 22           // поля шкалы по бокам

    var body: some View {
        Canvas { ctx, size in
            let mid = size.width / 2, halfW = mid - inset, base = size.height - 14
            // линия шкалы, гаснет к краям
            var line = Path()
            line.move(to: CGPoint(x: inset, y: base)); line.addLine(to: CGPoint(x: size.width - inset, y: base))
            ctx.stroke(line, with: .linearGradient(
                Gradient(colors: [.clear, hudText.opacity(0.35), .clear]),
                startPoint: CGPoint(x: inset, y: base), endPoint: CGPoint(x: size.width - inset, y: base)), lineWidth: 1)
            // риски
            let span = Double(halfW / ptPerDeg)
            let first = Int(((-turn - span) / stepDeg).rounded(.down)), last = Int(((-turn + span) / stepDeg).rounded(.up))
            for k in first...last {
                let x = mid + CGFloat(Double(k) * stepDeg + turn) * ptPerDeg
                let edge = Double(max(0, 1 - abs(x - mid) / halfW))
                let major = k % 5 == 0, home = k % 60 == 0      // home — исходное положение звезды
                var h: CGFloat = 6
                if major { h = 12 }
                if home { h = 18 }
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: base)); tick.addLine(to: CGPoint(x: x, y: base - h))
                var alpha = 0.4
                if major { alpha = 0.7 }
                if home { alpha = 1 }
                ctx.stroke(tick, with: .color(hudText.opacity(alpha * edge)), lineWidth: home ? 1.5 : 1)
            }
            // метка посередине: неподвижная золотая «блямба», как главная метка на борту корабля —
            // широкая, невысокая, бока прямые, верхний край скруглён дугой
            let gold = Color(red: 1, green: 0xd6 / 255, blue: 0x0a / 255)
            let mw: CGFloat = 4, top = base - 11, bottom = base + 3     // полуширина и края по высоте
            var centre = Path()
            centre.move(to: CGPoint(x: mid - mw, y: bottom))
            centre.addLine(to: CGPoint(x: mid - mw, y: top))
            centre.addQuadCurve(to: CGPoint(x: mid + mw, y: top), control: CGPoint(x: mid, y: top - 3.5))
            centre.addLine(to: CGPoint(x: mid + mw, y: bottom))
            centre.closeSubpath()
            ctx.fill(centre, with: .color(gold))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragStart == nil { dragStart = turn }
                    let raw = (dragStart ?? turn) + Double(g.translation.width / ptPerDeg)
                    var v = (raw + 180).truncatingRemainder(dividingBy: 360)
                    if v < 0 { v += 360 }
                    v -= 180
                    turn = v
                    onChange(v)
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

private struct ProbeControls: View {
    let hud: HUDModel
    let session: GameSession

    // пять оттенков красного от светлого к тёмному — те же, что у щупов в игре
    private let probeColors: [Color] = [
        Color(red: 1, green: 0xe0 / 255, blue: 0xd6 / 255),
        Color(red: 1, green: 0xab / 255, blue: 0x99 / 255),
        Color(red: 0xf8 / 255, green: 0x70 / 255, blue: 0x5e / 255),
        Color(red: 0xd4 / 255, green: 0x3b / 255, blue: 0x3b / 255),
        Color(red: 0x9c / 255, green: 0x24 / 255, blue: 0x40 / 255),
    ]
    private let buttonSize: CGFloat = 54
    @State private var pressed: Set<Int> = []      // какие кнопки щупов сейчас под пальцем
    @State private var starTurn: Double = 0        // градусы: поворот звезды секторов ползунком, от −180 до +180

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // переключатель варианта управления — только для теста
            Button {
                session.toggleControlMode()
            } label: {
                HStack(spacing: 6) {
                    Text("A").opacity(hud.controlMode == .buttons ? 1 : 0.35)
                    Text("B").opacity(hud.controlMode == .swipe ? 1 : 0.35)
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(hudText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            // ползунок над кнопками: крутит воображаемую звезду секторов — все стрелки разом
            if hud.controlMode == .buttons && !hud.probeArrows.isEmpty {
                // тянуть можно по всей нижней трети экрана — на поле всё равно некуда тыкать
                AimTape(turn: $starTurn) { session.setStarTurn(degrees: $0) }
                    .frame(height: UIScreen.main.bounds.height / 3)
                    .padding(.bottom, 4)
            }
            // один ряд: кнопки щупов (вариант А) и «отклеить последнее» того же размера справа
            HStack(spacing: 0) {
                if hud.controlMode == .buttons {
                    ForEach(Array(hud.probeFill.enumerated()), id: \.offset) { s, fill in
                        // оттенок красного = щуп. Кнопка полупрозрачная; чем больше на щупе, тем она ярче
                        // (стрелять нечем — почти пустая), выключенный щуп — едва виден. Тап бросает, долгое
                        // нажатие выключает / включает щуп: пока держат, кнопка плавно перекрашивается
                        // в то состояние, в которое перейдёт.
                        let off = s < hud.probeOff.count && hud.probeOff[s]
                        let hold = s < hud.probeHold.count ? Double(hud.probeHold[s]) : 0
                        let on = off ? hold : 1 - hold          // 1 — выглядит включённой, 0 — выключенной
                        let col = probeColors[s % probeColors.count]
                        // выключенную кнопку при удержании ведём к тому виду, какой она получит после включения
                        // (щуп с одним своим ядрышком), иначе в конце заливка появляется скачком
                        let bright = fill > 0 ? 0.15 + 0.5 * Double(fill) : (off ? 0.25 : 0.06)
                        Circle()
                            .fill(col.opacity(bright * on))
                            .overlay(Circle().stroke(col.opacity(0.2 + 0.35 * on), lineWidth: 2))
                            // кнопка по направлению: стрелка показывает, куда она стреляет
                            .overlay {
                                if s < hud.probeArrows.count {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(col.opacity(0.3 + 0.65 * on))
                                        .rotationEffect(.radians(Double(hud.probeArrows[s]) + .pi / 2))
                                }
                            }
                            .frame(width: buttonSize, height: buttonSize)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            // касание и отпускание ловим сами: короткое — выстрел, удержание — выключить / включить щуп
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !pressed.contains(s) { pressed.insert(s); session.pressBegan(s) }
                                    }
                                    .onEnded { _ in
                                        pressed.remove(s); session.pressEnded(s)
                                    }
                            )
                    }
                } else {
                    Spacer()
                }
                Button {
                    session.undoLast()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(hudText)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.black.opacity(0.35), in: Circle())
                        .overlay(Circle().stroke(hudText.opacity(0.5), lineWidth: 2))
                        .frame(maxWidth: hud.controlMode == .buttons ? .infinity : nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Реплики диспетчерской

private struct NarrationView: View {
    let hud: HUDModel

    var body: some View {
        if hud.narrationOpacity > 0 {
            Text(hud.narration)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(hudText)
                .shadow(color: .black, radius: 6, y: 2)
                .padding(.horizontal, 28)
                .opacity(hud.narrationOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: -150)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Победа

private struct WinView: View {
    let hud: HUDModel
    let session: GameSession

    var body: some View {
        if hud.showWin {
            VStack(spacing: 16) {
                Text(Strings.t("win.title"))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(winTitle)
                    .shadow(color: Color(red: 0xa0 / 255, green: 0x6b / 255, blue: 1), radius: 11, y: 2)
                    .kerning(3)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(hud.winSub)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(hudText)
                Button {
                    if hud.hasNext { session.press(.nextRound) } else { session.press(.restart) }
                } label: {
                    Text(hud.hasNext ? Strings.t("win.next") : Strings.t("win.restart"))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(Color(red: 0x0a / 255, green: 0x07 / 255, blue: 0x10 / 255))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(winButton, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: 120)
        }
    }
}

// MARK: - Подпись поглотителя

private struct ZoneLabel: View {
    let hud: HUDModel

    var body: some View {
        if let p = hud.zoneLabel {
            Text(Strings.t("zone.label"))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 205 / 255, green: 165 / 255, blue: 1).opacity(0.7))
                .position(p)
                .allowsHitTesting(false)
        }
    }
}
