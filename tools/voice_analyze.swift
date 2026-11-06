import AVFoundation
// разбор записи: длительность, пик, средняя громкость, шум, перегруз и разбивка на фразы по паузам
func db(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -120 }
for path in CommandLine.arguments.dropFirst() {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let fmt = file.processingFormat
    let n = AVAudioFrameCount(file.length)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
    try! file.read(into: buf)
    let ch = Int(fmt.channelCount), sr = fmt.sampleRate
    var mono = [Float](repeating: 0, count: Int(buf.frameLength))
    for c in 0..<ch { let p = buf.floatChannelData![c]; for i in 0..<mono.count { mono[i] += p[i] / Float(ch) } }
    var peak: Float = 0, clip = 0
    for v in mono { peak = max(peak, abs(v)); if abs(v) > 0.985 { clip += 1 } }
    // громкость окнами по 20 мс
    let win = Int(sr * 0.02)
    var rms: [Double] = []
    var i = 0
    while i + win <= mono.count { var s = 0.0; for k in i..<(i + win) { s += Double(mono[k] * mono[k]) }; rms.append((s / Double(win)).squareRoot()); i += win }
    let sorted = rms.sorted()
    let noise = sorted[sorted.count / 10], loud = sorted[sorted.count * 95 / 100]
    let thr = max(noise * 4, loud * 0.06)
    // фразы: участки выше порога, разделённые паузой от 0,22 с
    var segs: [(Int, Int)] = []
    var start = -1, quiet = 0
    for (k, v) in rms.enumerated() {
        if v > thr { if start < 0 { start = k }; quiet = 0 }
        else if start >= 0 { quiet += 1; if quiet >= 11 { segs.append((start, k - quiet)); start = -1; quiet = 0 } }
    }
    if start >= 0 { segs.append((start, rms.count - 1)) }
    print("== \((path as NSString).lastPathComponent): \(String(format: "%.1f", Double(mono.count) / sr)) с, пик \(String(format: "%.1f", db(Double(peak)))) дБ, перегруз \(clip) отсчётов, шум \(String(format: "%.0f", db(noise))) дБ, громкие места \(String(format: "%.0f", db(loud))) дБ")
    for (a, b) in segs where b - a >= 4 {
        let part = rms[a...b]
        let mean = (part.map { $0 * $0 }.reduce(0, +) / Double(part.count)).squareRoot()
        print(String(format: "   %5.2f–%5.2f с  длина %4.2f  громкость %5.1f дБ  пик %5.1f дБ", Double(a) * 0.02, Double(b + 1) * 0.02, Double(b - a + 1) * 0.02, db(mean), db(part.max()!)))
    }
}
