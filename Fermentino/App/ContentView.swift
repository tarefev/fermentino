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

    var body: some View {
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
