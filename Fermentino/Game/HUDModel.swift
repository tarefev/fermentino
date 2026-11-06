//
//  HUDModel.swift
//  Fermentino
//
//  Снимок состояния для SwiftUI-оверлеев (HUD, интро, победа, подпись зоны).
//

import Foundation
import Observation

/// Вариант управления (тест): А — кнопки по щупам, Б — свайп.
enum ControlMode {
    case buttons
    case swipe
}

enum MoleculeStatus {
    case notAssembled
    case haveAll
    case assembled
}

@Observable
final class HUDModel {
    var time = "0:00"
    var speed = 0
    var valence = 3
    var mass = 5000
    var bonds = 0
    var gravName = "норма"
    var gravIsNorm = true
    var mine = 0
    var goodBonds = 0
    var molStatus: MoleculeStatus = .notAssembled
    var showDebug = false
    var debugLine1 = ""
    var debugLine2 = ""
    var introOpacity: Double = 1
    var showWin = false
    var zoneLabel: CGPoint? = nil
    var ejectModeName = "opposite"
    var showBonds = true
    var winKind: WinKind = .star
    var introLines: [String] = []
    var introIcon = true
    var winSub = ""
    var hasNext = false
    var controls = RoundControls()
    var probesOn = false
    var probeFill: [Float] = []          // 0…1: заполненность щупа; 0 — стрелять нечем (перезарядка или выключен)
    var probeOff: [Bool] = []            // щуп выключен долгим нажатием
    var probeArrows: [Float] = []        // рад: куда стреляет кнопка (режим «по направлению»); пусто — стрелок нет
    var probeColorOffset = 0             // сдвиг оттенков кнопок по палитре
    var probeCharge: [Float] = []        // 0…1: восстановление щупа после выстрела (1 — готов)
    var probeMirror = false              // ряд кнопок зеркально перевёрнут (средняя смотрит вверх)
    var probeHold: [Float] = []          // 0…1: насколько дожато долгое нажатие на кнопку щупа
    var controlMode: ControlMode = .buttons
    var narration = ""
    var narrationOpacity: Double = 0
}
