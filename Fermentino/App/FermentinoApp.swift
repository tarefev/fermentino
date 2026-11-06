//
//  FermentinoApp.swift
//  Fermentino
//

import SwiftUI
import CoreText

@main
struct FermentinoApp: App {
    init() {
        // свои шрифты лежат в ресурсах приложения; подключаем их на старте
        // (Russo One, открытая лицензия OFL — текст в docs/RussoOne-OFL.txt)
        for name in ["RussoOne-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
