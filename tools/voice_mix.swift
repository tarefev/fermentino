import AVFoundation
// Подмешать звук (стук и т.п.) в реплику.
// Запуск: swift tools/voice_mix.swift реплика.m4a звук.m4a начало конец момент скорость усиление_дБ выход.m4a
//   начало, конец — какой отрезок звука взять (с); момент — куда в реплике поставить его начало (с);
//   скорость — 1 как есть, меньше 1 — ниже и длиннее (0.6: большая пустая бочка вместо кастрюли).
let a = CommandLine.arguments
let sr = 48000.0
let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
func load(_ path: String) -> [Float] {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let f = file.processingFormat
    let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: buf)
    var mono = [Float](repeating: 0, count: Int(buf.frameLength))
    for c in 0..<Int(f.channelCount) { let p = buf.floatChannelData![c]; for i in 0..<mono.count { mono[i] += p[i] / Float(f.channelCount) } }
    return mono
}
func save(_ y: [Float], to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let out = try! AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000])
    let ob = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(y.count))!
    ob.frameLength = AVAudioFrameCount(y.count)
    for k in 0..<y.count { ob.floatChannelData![0][k] = y[k] }
    try! out.write(from: ob)
}
var base = load(a[1])
let sfxAll = load(a[2])
let from = Int(Double(a[3])! * sr), to = min(sfxAll.count, Int(Double(a[4])! * sr))
let at = Int(Double(a[5])! * sr), speed = Double(a[6])!, gainDb = Double(a[7])!
let src = Array(sfxAll[from..<to])
// замедление простым пересчётом: звук становится ниже и длиннее
var sfx = [Float](repeating: 0, count: Int(Double(src.count) / speed))
for i in 0..<sfx.count {
    let pos = Double(i) * speed
    let i0 = Int(pos), fr = Float(pos - Double(i0))
    if i0 + 1 < src.count { sfx[i] = src[i0] * (1 - fr) + src[i0 + 1] * fr }
}
// GATE=-42: приглушить в звуке всё, что тише этого уровня (дБ), — ровный шум комнаты между событиями.
// Иначе при усилении тихой записи её фон превращается в постоянное шипение под всей репликой.
if let gateDb = Double(ProcessInfo.processInfo.environment["GATE"] ?? "") {
    let win = Int(sr * 0.02), thr = pow(10, gateDb / 20), floorGain: Float = 0.12
    var gain = [Float](repeating: floorGain, count: sfx.count)
    var i = 0
    while i < sfx.count {
        let e = min(sfx.count, i + win)
        var sum = 0.0
        for k in i..<e { sum += Double(sfx[k] * sfx[k]) }
        let open = (sum / Double(e - i)).squareRoot() > thr
        // открытое окно держим ещё 0,12 с после события, чтобы не рубить хвосты
        if open { for k in max(0, i - win)..<min(sfx.count, e + Int(sr * 0.12)) { gain[k] = 1 } }
        i = e
    }
    // сглаживаем переходы, чтобы шум не включался щелчком
    var g: Float = floorGain
    let up: Float = 1 / Float(sr * 0.01), down: Float = 1 / Float(sr * 0.08)
    for k in 0..<sfx.count {
        if gain[k] > g { g = min(gain[k], g + up) } else { g = max(gain[k], g - down) }
        sfx[k] *= g
    }
}
// SFXLIMIT=0.12: мягко срезать редкие резкие пики звука выше этого уровня, чтобы один щелчок не задавал громкость всему
if let lim = Float(ProcessInfo.processInfo.environment["SFXLIMIT"] ?? "") {
    for i in 0..<sfx.count { sfx[i] = tanh(sfx[i] / lim) * lim }
}
// громкость: пик звука относительно пика реплики
let basePeak = base.map { abs($0) }.max() ?? 1, sfxPeak = sfx.map { abs($0) }.max() ?? 1
let g = basePeak / max(sfxPeak, 1e-6) * Float(pow(10, gainDb / 20))
let fade = Int(sr * 0.15)
for i in 0..<min(fade, sfx.count) { sfx[sfx.count - 1 - i] *= Float(i) / Float(fade) }   // хвост звона уходит плавно
if base.count < at + sfx.count { base += [Float](repeating: 0, count: at + sfx.count - base.count) }
for i in 0..<sfx.count { base[at + i] += sfx[i] * g }
let peak = base.map { abs($0) }.max() ?? 1
let norm = Float(pow(10, -1.0 / 20)) / peak
save(base.map { $0 * norm }, to: a[8])
print("готово:", a[8])
