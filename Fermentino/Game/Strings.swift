//
//  Strings.swift
//  Fermentino
//
//  Таблица строк: ключ → текст на языке устройства (en по умолчанию, ru если система русская).
//  Весь игровой текст (реплики, баннеры) — только отсюда.
//  Имена: Юрик и Сергей Павлович. Фамилии (Гагарин, Королёв) в тексте не звучат.
//  «Юрий Алексеевич» — только для торжественных случаев (награда), не когда на него орут.
//

import Foundation

enum Strings {
    private static let ru: [String: String] = [
        "zone.label": "ПОГЛОТИТЕЛЬ",
        "win.title": "ИНЦИДЕНТ ИСЧЕРПАН",
        "win.next": "Дальше →",
        "win.restart": "Рестарт ⟳",
        "win.molecule": "фермент собран и поглощён",
        "win.flight": "никто не погиб. наверное.",
        "intro.molecule.1": "СОБЕРИ ЭТОТ ФЕРМЕНТ И ОТНЕСИ",
        "intro.molecule.2": "ЕГО В ПОГЛОТИТЕЛЬ",
        "flight.start": "Юрик! Взорвалось. Это ЭКСПЕРИМЕНТ. Дуй к поглотителю!",
        "flight.incoming": "Юрик! Летит инертон. НЕ ТРОГАЙ.",
        "flight.caught": "Прилип. Кинь его в другую сторону. Отдача, Юрик! Ньютон!",
        "flight.moving": "Поехал! Я гений.",
        "flight.done": "Втянуло. Никому ни слова, Юрик. Рюмка «Сталичной».",
    ]

    private static let en: [String: String] = [
        "zone.label": "ABSORBER",
        "win.title": "INCIDENT CLOSED",
        "win.next": "Next →",
        "win.restart": "Restart ⟳",
        "win.molecule": "the ferment is assembled and absorbed",
        "win.flight": "nobody died. probably.",
        "intro.molecule.1": "ASSEMBLE THIS FERMENT AND BRING IT",
        "intro.molecule.2": "TO THE ABSORBER",
        "flight.start": "Yurik! It blew up. It's an EXPERIMENT. Get to the absorber!",
        "flight.incoming": "Yurik! Inerton incoming. DON'T TOUCH IT.",
        "flight.caught": "It stuck. Throw it the other way. Recoil, Yurik! Newton!",
        "flight.moving": "You're moving! I'm a genius.",
        "flight.done": "It took you. Not a word, Yurik. One shot of Stolee.",
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
