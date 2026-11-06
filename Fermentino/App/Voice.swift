//
//  Voice.swift
//  Fermentino
//
//  Озвучка: проигрывает реплику профессора из ресурсов приложения. Одна реплика за раз — новая
//  обрывает предыдущую.
//

import AVFoundation

final class Voice {
    static let shared = Voice()
    private var player: AVAudioPlayer?

    private init() {
        // голос слышен и при выключенном звонке и не глушит музыку, которая играет у пользователя
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Проиграть файл `name`.m4a из ресурсов; если такого нет — тишина (реплика ещё не записана).
    func play(_ name: String, delay: TimeInterval = 0) {
        stop()
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return }
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p
        p.prepareToPlay()
        p.play(atTime: p.deviceCurrentTime + delay)
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
