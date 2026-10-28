//
//  Progress.swift
//  Fermentino
//
//  Сквозной прогресс: номер текущего тура. Назад пути нет — только вперёд.
//  Пока локально (UserDefaults); позже сюда же подключится бэк.
//

import Foundation

enum Progress {
    private static let key = "fermentino.round"

    static var roundIndex: Int {
        get { min(max(0, UserDefaults.standard.integer(forKey: key)), Rounds.all.count - 1) }
        set { UserDefaults.standard.set(min(max(0, newValue), Rounds.all.count - 1), forKey: key) }
    }

    static var hasNext: Bool { roundIndex + 1 < Rounds.all.count }

    private static let prologueKey = "fermentino.prologueSeen"
    static var prologueSeen: Bool {
        get { UserDefaults.standard.bool(forKey: prologueKey) }
        set { UserDefaults.standard.set(newValue, forKey: prologueKey) }
    }
}
