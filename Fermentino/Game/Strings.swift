//
//  Strings.swift
//  Fermentino
//
//  Таблица строк: ключ → текст на языке устройства (en по умолчанию, ru если система русская).
//  Весь игровой текст (реплики, баннеры) — только отсюда.
//

import Foundation

enum Strings {
    private static let ru: [String: String] = [
        "zone.label": "ПОГЛОТИТЕЛЬ",
        "win.title": "ВЫ ПОБЕДИЛИ",
        "win.next": "Дальше →",
        "win.restart": "Рестарт ⟳",
        "win.molecule": "фермент собран и поглощён",
        "win.flight": "инцидент исчерпан",
        "intro.molecule.1": "СОБЕРИ ЭТОТ ФЕРМЕНТ И ОТНЕСИ",
        "intro.molecule.2": "ЕГО В ПОГЛОТИТЕЛЬ",
        "flight.start": "Тесей, это диспетчерская. Произошла нештатная ситуация. Это была случайность. Доберитесь до поглотителя.",
        "flight.incoming": "К вам идёт инертон. Не препятствуйте.",
        "flight.caught": "Инертон захвачен. Выбросьте его в сторону от цели. Отдача доставит вас.",
        "flight.moving": "Движение зафиксировано. Продолжайте.",
        "flight.done": "Поглотитель принял объект. Инцидент исчерпан.",
    ]

    private static let en: [String: String] = [
        "zone.label": "ABSORBER",
        "win.title": "YOU WIN",
        "win.next": "Next →",
        "win.restart": "Restart ⟳",
        "win.molecule": "the ferment is assembled and absorbed",
        "win.flight": "the incident is closed",
        "intro.molecule.1": "ASSEMBLE THIS FERMENT AND BRING IT",
        "intro.molecule.2": "TO THE ABSORBER",
        "flight.start": "Theseus, this is Control. There has been an incident. It was an accident. Reach the absorber.",
        "flight.incoming": "An inerton is heading your way. Do not interfere.",
        "flight.caught": "Inerton captured. Throw it away from the target. The recoil will carry you.",
        "flight.moving": "Movement confirmed. Proceed.",
        "flight.done": "The absorber has accepted the object. The incident is closed.",
    ]

    /// Пока игра целиком на английском (продаём американцам); русский в таблице — задел на локализацию.
    static let forceEnglish = true

    static var isRussian: Bool {
        if forceEnglish { return false }
        return Locale.current.language.languageCode?.identifier == "ru"
    }

    static func t(_ key: String) -> String {
        if isRussian, let s = ru[key] { return s }
        if let s = en[key] { return s }
        return key
    }
}
