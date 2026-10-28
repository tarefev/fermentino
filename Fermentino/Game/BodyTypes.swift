//
//  BodyTypes.swift
//  Fermentino
//
//  Константы типов/флагов тела — зеркало #define в Simulation.metal.
//

enum BodyType {
    static let core: UInt32 = 0
    static let atom: UInt32 = 1
    static let anchor: UInt32 = 2
}

enum BodyFlag {
    static let captured: UInt32 = 1
    static let mine: UInt32 = 4
}

extension Body {
    var isCaptured: Bool { flags & BodyFlag.captured != 0 }
    var isMine: Bool { flags & BodyFlag.mine != 0 }
}
