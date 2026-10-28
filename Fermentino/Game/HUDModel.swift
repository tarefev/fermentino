//
//  HUDModel.swift
//  Fermentino
//
//  Снимок состояния для SwiftUI-оверлеев (HUD, интро, победа, подпись зоны).
//

import Foundation
import Observation

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
}
