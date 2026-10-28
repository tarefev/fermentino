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
        "flight.start": "Юрик! Юрик, ты меня слышишь?! Конечно оно взорвалось, это ЭКСПЕРИМЕНТ, болван! Никто не погиб. Наверное. Доберись до поглотителя, потом объясню!",
        "flight.incoming": "Товарищ Гагарин, доложить! Видишь, летит? Это инертон. Ничего не трогай. НИ-ЧЕ-ГО.",
        "flight.caught": "Прилип, хорошо. Теперь выкинь его в сторону от того, куда тебе надо. Отдача, Юрик! Ньютон! Третий класс, чёрт тебя дери!",
        "flight.moving": "Поехал! Видишь? Я гений. Давай дальше, товарищ, дальше.",
        "flight.done": "Втянуло. Хорошо. Никому ни слова, Юрик. НИКОМУ. Рюмка «Столичной». Для нервов.",
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
        "flight.start": "Yurik! Yurik, do you hear me?! Of course it blew up, it's an EXPERIMENT, you blockhead! Nobody died. Probably. Get to the absorber, I'll explain later!",
        "flight.incoming": "Comrade Gagarin, report! See that thing coming at you? That's an inerton. Don't touch anything. DON'T. TOUCH. ANYTHING.",
        "flight.caught": "Good, it stuck. Now throw it out, away from where you want to go. Recoil, Yurik! Newton! Third grade, damn it!",
        "flight.moving": "You're moving! See? I'm a genius. Keep going, comrade, keep going.",
        "flight.done": "It took you. Good. Not a word to anyone, Yurik. ANYONE. One shot of Stoli. For the nerves.",
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
