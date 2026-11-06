import AVFoundation
// «Плёночный» звук: как дорожка старого мультфильма. Узкая полоса частот, мягкий перегруз, шипение и редкие щелчки.
// Запуск: swift tools/voice_film.swift вход.m4a выход.m4a
let args = CommandLine.arguments
let sr = 48000.0
let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
let file = try! AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
try! file.read(into: inBuf)
var x = [Float](repeating: 0, count: Int(inBuf.frameLength))
for c in 0..<Int(file.processingFormat.channelCount) {
    let p = inBuf.floatChannelData![c]
    for i in 0..<x.count { x[i] += p[i] / Float(file.processingFormat.channelCount) }
}
// фильтр второго порядка (RBJ): тип — "hp" или "lp"
func biquad(_ x: [Float], type: String, f: Double, q: Double) -> [Float] {
    let w = 2 * Double.pi * f / sr, cs = cos(w), al = sin(w) / (2 * q)
    var b0 = 0.0, b1 = 0.0, b2 = 0.0
    if type == "hp" { b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2 } else { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2 }
    let a0 = 1 + al, a1 = -2 * cs, a2 = 1 - al
    var y = [Float](repeating: 0, count: x.count)
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    for i in 0..<x.count {
        let v = Double(x[i])
        let o = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2 = x1; x1 = v; y2 = y1; y1 = o
        y[i] = Float(o)
    }
    return y
}
// полоса старой оптической дорожки: примерно 200–4500 Гц, дважды с каждой стороны для крутого спада
var y = biquad(biquad(x, type: "hp", f: 210, q: 0.7), type: "hp", f: 210, q: 0.7)
y = biquad(biquad(y, type: "lp", f: 4500, q: 0.7), type: "lp", f: 4500, q: 0.7)
// мягкий перегруз: громкие места слегка хрипят
let drive: Float = 2.6
let peak0 = y.map { abs($0) }.max() ?? 1
for i in 0..<y.count { y[i] = tanh(y[i] / peak0 * drive) / tanh(drive) }
// Старые шумы. Уровни задаются снаружи, 0 выключает:
//   HISS    — глухой широкий шум плёнки (300–3000 Гц; узкая полоса на верхах звучала как свист), по умолчанию 0.004
//   CRACKLE — частый мелкий треск, штук в секунду, по умолчанию 9
//   POP     — редкие крупные щелчки раз в 1–3 с, их громкость, по умолчанию 0.07
//   WOW     — «плавание» звука, как на растянутой плёнке: доля отклонения высоты, по умолчанию 0.003
func env(_ k: String, _ d: Float) -> Float { Float(ProcessInfo.processInfo.environment[k] ?? "") ?? d }
let hissLevel = env("HISS", 0.004), crackle = env("CRACKLE", 9), popLevel = env("POP", 0.07), wow = env("WOW", 0.003)
var seed: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) * 2 - 1 }

// плавание: звук читается с переменной задержкой — медленная волна (0,6 Гц) и мелкая дрожь (7 Гц)
if wow > 0 {
    let slowA = Double(wow) * sr / (2 * Double.pi * 0.6), fastA = Double(wow) * 0.25 * sr / (2 * Double.pi * 7)
    let base = slowA + fastA + 2
    var w = [Float](repeating: 0, count: y.count)
    for n in 0..<y.count {
        let t = Double(n) / sr
        let pos = Double(n) - base - slowA * sin(2 * Double.pi * 0.6 * t) - fastA * sin(2 * Double.pi * 7 * t)
        if pos < 0 { continue }
        let i0 = Int(pos), fr = Float(pos - Double(i0))
        if i0 + 1 < y.count { w[n] = y[i0] * (1 - fr) + y[i0 + 1] * fr }
    }
    y = w
}
if hissLevel > 0 {
    var hiss = [Float](repeating: 0, count: y.count)
    for i in 0..<hiss.count { hiss[i] = rnd() }
    hiss = biquad(biquad(hiss, type: "hp", f: 300, q: 0.7), type: "lp", f: 3000, q: 0.7)
    for i in 0..<y.count { y[i] += hiss[i] * hissLevel }
}
// щелчок: резкий фронт и короткий спад
func click(at i: Int, amp: Float, len: Int) {
    if i + len >= y.count { return }
    let sign: Float = rnd() > 0 ? 1 : -1
    for k in 0..<len {
        var a = amp
        if k >= 3 { a = amp * exp(-Float(k - 3) / Float(len) * 5) }
        y[i + k] += a * sign
    }
}
if crackle > 0 {
    // мелкий треск: случайные моменты, разная громкость, изредка пачками
    var i = 0
    while i < y.count {
        let gap: Double = Double(rnd() + 1.02) / Double(crackle)
        i += max(1, Int(gap * sr))
        click(at: i, amp: 0.008 + abs(rnd()) * 0.022, len: 14)
    }
}
if popLevel > 0 {
    var i = 0
    while i < y.count {
        let wait: Double = 1.0 + Double(rnd() + 1) * 1.0
        i += Int(wait * sr)
        click(at: i, amp: popLevel * (0.6 + abs(rnd()) * 0.6), len: 48)
    }
}
let peak = y.map { abs($0) }.max() ?? 1
let g = Float(pow(10, -1.0 / 20)) / peak
// запись — в отдельной функции: файл дописывается и закрывается, когда она заканчивается
func save(_ y: [Float], gain: Float, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let out = try! AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000])
    let ob = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(y.count))!
    ob.frameLength = AVAudioFrameCount(y.count)
    for k in 0..<y.count { ob.floatChannelData![0][k] = y[k] * gain }
    try! out.write(from: ob)
}
save(y, gain: g, to: args[2])
print("готово:", args[2])
