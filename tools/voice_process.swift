import AVFoundation
import AudioToolbox
// обработка дубля: 1) «как есть» — обрезка тишины и выравнивание громкости; 2) «монтаж» — куски реплики
// расставлены по громкости и паузам по заданному рисунку, голос чуть ниже и плотнее
let args = CommandLine.arguments
let inPath = args[1], outPlain = args[2], outEdit = args[3]
let sr = 48000.0
let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
func db(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -120 }
func lin(_ d: Double) -> Float { Float(pow(10, d / 20)) }

func load(_ path: String) -> [Float] {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let f = file.processingFormat
    let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: buf)
    var mono = [Float](repeating: 0, count: Int(buf.frameLength))
    let ch = Int(f.channelCount)
    for c in 0..<ch { let p = buf.floatChannelData![c]; for i in 0..<mono.count { mono[i] += p[i] / Float(ch) } }
    return mono
}
func write(_ x: [Float], _ path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000]
    let file = try! AVAudioFile(forWriting: url, settings: settings)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(x.count))!
    buf.frameLength = AVAudioFrameCount(x.count)
    x.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
    try! file.write(from: buf)
}
func normalize(_ x: [Float], peakDb: Double) -> [Float] {
    let peak = x.map { abs($0) }.max() ?? 1
    let g = lin(peakDb) / max(peak, 1e-6)
    return x.map { $0 * g }
}
// куски речи по паузам (как в analyze.swift)
func segments(_ mono: [Float]) -> (segs: [(Int, Int)], noise: Double) {
    let win = Int(sr * 0.02)
    var rms: [Double] = []
    var i = 0
    while i + win <= mono.count { var s = 0.0; for k in i..<(i + win) { s += Double(mono[k] * mono[k]) }; rms.append((s / Double(win)).squareRoot()); i += win }
    let sorted = rms.sorted()
    let noise = sorted[sorted.count / 10], loud = sorted[sorted.count * 95 / 100]
    let thr = max(noise * 4, loud * 0.06)
    var segs: [(Int, Int)] = []
    var start = -1, quiet = 0
    for (k, v) in rms.enumerated() {
        if v > thr { if start < 0 { start = k }; quiet = 0 }
        else if start >= 0 { quiet += 1; if quiet >= 11 { segs.append((start, k - quiet)); start = -1; quiet = 0 } }
    }
    if start >= 0 { segs.append((start, rms.count - 1)) }
    return (segs.filter { $0.1 - $0.0 >= 4 }.map { ($0.0 * win, ($0.1 + 1) * win) }, noise)
}
func rmsDb(_ x: ArraySlice<Float>) -> Double { db((x.map { Double($0 * $0) }.reduce(0, +) / Double(max(1, x.count))).squareRoot()) }

// голос: чуть ниже, плотнее, с подчёркнутой серединой. Делается ДО расстановки громкости: сжатие выравнивает
// куски между собой, и рисунок, наложенный раньше него, оно бы стёрло.
func voice(_ x: [Float]) -> [Float] {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let pitch = AVAudioUnitTimePitch()
    pitch.pitch = -130                      // сотые полутона: чуть больше тона вниз
    pitch.rate = 1.0
    let eq = AVAudioUnitEQ(numberOfBands: 3)
    eq.bands[0].filterType = .highPass; eq.bands[0].frequency = 85; eq.bands[0].bypass = false
    eq.bands[1].filterType = .parametric; eq.bands[1].frequency = 190; eq.bands[1].bandwidth = 1.2; eq.bands[1].gain = 2.5; eq.bands[1].bypass = false
    eq.bands[2].filterType = .parametric; eq.bands[2].frequency = 2800; eq.bands[2].bandwidth = 1.4; eq.bands[2].gain = 3.5; eq.bands[2].bypass = false
    func unit(_ sub: OSType) -> AVAudioUnitEffect {
        AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: sub, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    }
    let dyn = unit(kAudioUnitSubType_DynamicsProcessor)
    let limiter = unit(kAudioUnitSubType_PeakLimiter)
    for n in [player, pitch, eq, dyn, limiter] as [AVAudioNode] { engine.attach(n) }
    engine.connect(player, to: pitch, format: fmt)
    engine.connect(pitch, to: eq, format: fmt)
    engine.connect(eq, to: dyn, format: fmt)
    engine.connect(dyn, to: limiter, format: fmt)
    engine.connect(limiter, to: engine.mainMixerNode, format: fmt)
    AudioUnitSetParameter(dyn.audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -26, 0)
    AudioUnitSetParameter(dyn.audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 9, 0)
    AudioUnitSetParameter(dyn.audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.004, 0)
    AudioUnitSetParameter(dyn.audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.12, 0)
    AudioUnitSetParameter(dyn.audioUnit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 5, 0)
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
    try! engine.start()
    let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(x.count))!
    src.frameLength = AVAudioFrameCount(x.count)
    x.withUnsafeBufferPointer { src.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
    player.scheduleBuffer(src, at: nil)
    player.play()
    var out: [Float] = []
    let rbuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    let total = x.count + Int(sr * 0.4)
    while out.count < total {
        let status = try! engine.renderOffline(min(4096, AVAudioFrameCount(total - out.count)), to: rbuf)
        if status != .success { break }
        let p = rbuf.floatChannelData![0]
        for i in 0..<Int(rbuf.frameLength) { out.append(p[i]) }
    }
    player.stop(); engine.stop()
    return out
}

// эхо подвала: для смеха — чтобы он раскатывался по лаборатории, а не обрывался
func reverb(_ x: [Float], wet: Float, tail: Double) -> [Float] {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let rv = AVAudioUnitReverb()
    rv.loadFactoryPreset(.largeChamber)
    rv.wetDryMix = wet
    engine.attach(player); engine.attach(rv)
    engine.connect(player, to: rv, format: fmt)
    engine.connect(rv, to: engine.mainMixerNode, format: fmt)
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
    try! engine.start()
    let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(x.count))!
    src.frameLength = AVAudioFrameCount(x.count)
    x.withUnsafeBufferPointer { src.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
    player.scheduleBuffer(src, at: nil)
    player.play()
    var out: [Float] = []
    let rbuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    let total = x.count + Int(sr * tail)
    while out.count < total {
        let status = try! engine.renderOffline(min(4096, AVAudioFrameCount(total - out.count)), to: rbuf)
        if status != .success { break }
        let p = rbuf.floatChannelData![0]
        for i in 0..<Int(rbuf.frameLength) { out.append(p[i]) }
    }
    player.stop(); engine.stop()
    // хвост эха плавно уходит в ноль
    let f = min(out.count, Int(sr * 0.5))
    for i in 0..<f { out[out.count - 1 - i] *= Float(i) / Float(f) }
    return out
}

let mono = load(inPath)
let (segs0, _) = segments(mono)
// 1) как есть: от первого куска до последнего с полями, пик −1 дБ
let pad = Int(sr * 0.15)
write(normalize(Array(mono[max(0, segs0.first!.0 - pad)..<min(mono.count, segs0.last!.1 + pad)]), peakDb: -1), outPlain)

// 2) монтаж: сначала голос, потом рисунок реплики — громкость каждого куска относительно среднего (дБ)
// и пауза после него (с)
let voiced = voice(mono)
// куски ищем по исходной записи: после сжатия тихие места поднимаются и соседние куски слипаются.
// Обработка сдвигает звук на доли секунды — сдвиг берём по началу первого куска.
// сдвиг ищем честно: при каком смещении огибающая обработанного звука лучше всего ложится на исходную
func envelope(_ x: [Float], hop: Int) -> [Float] {
    var e: [Float] = []
    var i = 0
    while i + hop <= x.count { var s: Float = 0; for k in i..<(i + hop) { s += abs(x[k]) }; e.append(s / Float(hop)); i += hop }
    return e
}
let hop = Int(sr * 0.005)
let e0 = envelope(mono, hop: hop), e1 = envelope(voiced, hop: hop)
var bestLag = 0
var bestScore: Float = -1
for lag in -60...60 {                       // ±300 мс
    var sc: Float = 0
    var k = max(0, -lag)
    while k < e0.count && k + lag < e1.count { sc += e0[k] * e1[k + lag]; k += 1 }
    if sc > bestScore { bestScore = sc; bestLag = lag }
}
let shift = bestLag * hop
var base = segs0
// SEGS="0.68-1.72,2.16-2.80,…" — куски заданы вручную, в секундах исходной записи
if let manual = ProcessInfo.processInfo.environment["SEGS"] {
    base = manual.split(separator: ",").compactMap { part -> (Int, Int)? in
        let ab = part.split(separator: "-").compactMap { Double($0) }
        if ab.count != 2 { return nil }
        return (Int(ab[0] * sr), Int(ab[1] * sr))
    }
}
var segs = base.map { (max(0, $0.0 + shift), min(voiced.count, $0.1 + shift)) }
print("кусков:", segs.count, "сдвиг обработки, мс:", Int(Double(shift) / sr * 1000))
if let use = Int(ProcessInfo.processInfo.environment["USE"] ?? ""), use < segs.count { segs = Array(segs.prefix(use)) }
// рисунок можно задать снаружи (PATTERN и PAUSES через запятую), а лишние куски в хвосте отбросить (USE=N)
func list(_ k: String) -> [Double]? { ProcessInfo.processInfo.environment[k]?.split(separator: ",").compactMap { Double($0) } }
let targetDb: [Double] = list("PATTERN") ?? [-5, 2.5, -0.5, 1, 3, -4, -2, -4, -6]
let pauseAfter: [Double] = list("PAUSES") ?? [0.30, 0.45, 0.18, 0.18, 0.65, 0.28, 0.45, 0.85, 0]
var edit: [Float] = []
if segs.count == targetDb.count {
    let levels = segs.map { rmsDb(voiced[$0.0..<$0.1]) }
    let mean = levels.reduce(0, +) / Double(levels.count)
    // фон для пауз: кусок записи перед первой фразой; если его нет — самый тихий участок между кусками
    var tone: [Float] = []
    let t0 = segs[0].0 - Int(sr * 0.3), t1 = segs[0].0 - Int(sr * 0.06)
    if t0 >= 0 && t1 > t0 { tone = Array(voiced[t0..<t1]) }
    if tone.count < Int(sr * 0.1) && segs.count > 1 {
        let g0 = segs[0].1 + Int(sr * 0.06), g1 = segs[1].0 - Int(sr * 0.06)
        if g1 > g0 { tone = Array(voiced[g0..<g1]) }
    }
    let fade = Int(sr * 0.012), lead = ProcessInfo.processInfo.environment["SEGS"] != nil ? 0 : Int(sr * 0.06)   // ручные куски уже с полями
    for (k, s) in segs.enumerated() {
        let gainDb = targetDb[k] - (levels[k] - mean)
        let g = lin(gainDb)
        let a = max(0, s.0 - lead), b = min(voiced.count, s.1 + lead)
        var piece = Array(voiced[a..<b]).map { $0 * g }
        for i in 0..<min(fade, piece.count) { let t = Float(i) / Float(fade); piece[i] *= t; piece[piece.count - 1 - i] *= t }
        // LAUGH=1: последний кусок — смех, ему даём эхо подвала
        if k == segs.count - 1, ProcessInfo.processInfo.environment["LAUGH"] == "1" { piece = reverb(piece, wet: 38, tail: 1.6) }
        edit += piece
        let gap = Int(pauseAfter[k] * sr)
        for i in 0..<gap { edit.append(tone.isEmpty ? 0 : tone[i % tone.count] * 0.6) }
    }
} else {
    print("число кусков не совпало с рисунком — без перестановки")
    edit = voiced
}
write(normalize(edit, peakDb: -1), outEdit)
print(String(format: "готово: монтаж %.1f с", Double(edit.count) / sr))
