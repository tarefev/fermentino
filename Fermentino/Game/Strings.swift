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
        "win.title": "ИНЦИДЕНТ ИСЧЕРПАН",
        "win.next": "Дальше →",
        "win.restart": "Рестарт ⟳",
        "win.molecule": "фермент собран и поглощён",
        "win.flight": "никто не погиб. наверное.",
        "intro.molecule.1": "СОБЕРИ ЭТОТ ФЕРМЕНТ И ОТНЕСИ",
        "intro.molecule.2": "ЕГО В ПОГЛОТИТЕЛЬ",
        "flight.start": "Юрик! Конечно взорвалось, это ЭКСПЕРИМЕНТ! Никто не погиб. Наверное. Дуй к поглотителю!",
        "flight.incoming": "Товарищ Гагарин! Летит инертон. НИЧЕГО НЕ ТРОГАЙ.",
        "flight.caught": "Прилип. Теперь выкинь его в другую сторону. Отдача, Юрик! Ньютон! Третий класс!",
        "flight.moving": "Поехал! Я гений. Давай, товарищ.",
        "flight.done": "Втянуло. Никому ни слова, Юрик. Рюмка «Сталичной». Для нервов.",
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
        "flight.start": "Yurik! Of course it blew up, it's an EXPERIMENT! Nobody died. Probably. Get to the absorber!",
        "flight.incoming": "Comrade Gagarin! That thing flying at you is an inerton. DON'T TOUCH ANYTHING.",
        "flight.caught": "It stuck. Now throw it the other way. Recoil, Yurik! Newton! Third grade!",
        "flight.moving": "You're moving! I'm a genius. Keep going, comrade.",
        "flight.done": "It took you. Not a word to ANYONE, Yurik. One shot of Stolee. For the nerves.",
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
