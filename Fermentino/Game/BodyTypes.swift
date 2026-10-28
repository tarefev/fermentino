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
    static let dust: UInt32 = 3     // пыль: гравитация и контакт как у всех, но не инертон
}

enum BodyFlag {
    static let captured: UInt32 = 1
    static let mine: UInt32 = 4
    static let molCore: UInt32 = 8
}

extension Body {
    var isCaptured: Bool { flags & BodyFlag.captured != 0 }
    var isMine: Bool { flags & BodyFlag.mine != 0 }
    var isMolCore: Bool { flags & BodyFlag.molCore != 0 }
}
