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
        "prologue.1": "Смотри, Юрик. Смотри! Он ест грязь, он пьёт тьму, и он строит молекулы. Зачем? Наука, Юрик. Наука не спрашивает. Полезай.",
        "prologue.2": "Пошло! Громче! Да! Запишите, все: это была случайность.",
        "prologue.3": "Юрик? Юрик, ты меня слышишь? Хорошо. Ты жив, ты внутри, ты мой. Ничего не трогай.",
        "prologue.tagline": "Наука требует жертв.\nЮрик вызвался.",
        "win.title": "ИНЦИДЕНТ ИСЧЕРПАН",
        "win.next": "Дальше →",
        "win.restart": "Рестарт ⟳",
        "win.molecule": "фермент собран и поглощён",
        "win.flight": "никто не погиб. наверное.",
        "intro.molecule.1": "СОБЕРИ ЭТОТ ФЕРМЕНТ И ОТНЕСИ",
        "intro.molecule.2": "ЕГО В ПОГЛОТИТЕЛЬ",
        "flight.start": "Дуй к поглотителю, Юрик!",
        "flight.incoming": "Юрик! Летит инертон. НЕ ТРОГАЙ.",
        "flight.caught": "Прилип. Кинь его в другую сторону. Отдача, Юрик! Ньютон!",
        "flight.moving": "Поехал! Я гений.",
        "flight.done": "Втянуло. Никому ни слова, Юрик. Рюмка «Сталичной».",
    ]

    private static let en: [String: String] = [
        "zone.label": "ABSORBER",
        "prologue.1": "Look, Yurik. Look! It eats the dirt, it drinks the dark, and it builds molecules. What for? Science, Yurik. Science never asks. Get in.",
        "prologue.2": "There it goes! Louder! Yes! Write it down, all of you: it was an accident.",
        "prologue.3": "Yurik? Yurik, can you hear me? Good. You're alive, you're inside, you're mine. Don't touch anything.",
        "prologue.tagline": "Science demands sacrifice.\nYurik volunteered.",
        "win.title": "INCIDENT CLOSED",
        "win.next": "Next →",
        "win.restart": "Restart ⟳",
        "win.molecule": "the ferment is assembled and absorbed",
        "win.flight": "nobody died. probably.",
        "intro.molecule.1": "ASSEMBLE THIS FERMENT AND BRING IT",
        "intro.molecule.2": "TO THE ABSORBER",
        "flight.start": "Get to the absorber, Yurik!",
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
