//
//  Voice.swift
//  Fermentino
//
//  Озвучка: проигрывает реплику профессора из ресурсов приложения. Одна реплика за раз — новая
//  обрывает предыдущую.
//

import AVFoundation

final class Voice: NSObject, AVAudioPlayerDelegate {
    static let shared = Voice()
    private var player: AVAudioPlayer?
    private var onEnd: (() -> Void)?
    private var ended = false
    private var startAt: TimeInterval = 0
    private(set) var name: String?

    /// Сколько секунд записи `name` уже прозвучало: nil — она сейчас не играет и не доиграла (текст показываем
    /// целиком), бесконечность — доиграла до конца.
    func time(of name: String) -> Double? {
        guard self.name == name, let p = player else { return nil }
        if ended { return .infinity }
        return max(0, p.deviceCurrentTime - startAt)
    }

    private override init() {
        super.init()
        // голос слышен и при выключенном звонке и не глушит музыку, которая играет у пользователя
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Проиграть файл `name`.m4a из ресурсов; если такого нет — тишина (реплика ещё не записана).
    /// `onEnd` вызывается, когда реплика доиграла до конца сама (не когда её оборвали).
    func play(_ name: String, delay: TimeInterval = 0, onEnd: (() -> Void)? = nil) {
        stop()
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return }
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p
        self.name = name
        ended = false
        self.onEnd = onEnd
        p.delegate = self
        p.prepareToPlay()
        startAt = p.deviceCurrentTime + delay
        p.play(atTime: startAt)
    }

    func stop() {
        onEnd = nil
        player?.stop()
        player = nil
        name = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        ended = true
        let done = onEnd
        onEnd = nil
        done?()
    }
}
