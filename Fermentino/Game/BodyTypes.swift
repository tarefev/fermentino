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
    static let tip: UInt32 = 4      // ядрышко на конце щупа: часть корабля, всегда прибито к концу щупа
}

enum BodyFlag {
    static let captured: UInt32 = 1
    static let mine: UInt32 = 4
    static let molCore: UInt32 = 8
    static let held: UInt32 = 16     // ядро комка: прибито к концу щупа хоста
    static let member: UInt32 = 32   // зерно комка: держится притяжением своего щупа и контактом
    static let group: UInt32 = 48    // held | member
    static let apple: UInt32 = 64    // «яблоко»: особый груз, который ловит только рука в режиме яблок
}

extension Body {
    var isCaptured: Bool { flags & BodyFlag.captured != 0 }
    var isMine: Bool { flags & BodyFlag.mine != 0 }
    var isMolCore: Bool { flags & BodyFlag.molCore != 0 }
}
