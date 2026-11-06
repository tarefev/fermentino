import Speech
import Foundation
// распознать речь в файле и напечатать слова с временем
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let status = SFSpeechRecognizer.authorizationStatus()
print("authorization:", status.rawValue)
guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), rec.isAvailable else { print("recognizer unavailable"); exit(1) }
print("onDevice:", rec.supportsOnDeviceRecognition)
let req = SFSpeechURLRecognitionRequest(url: url)
req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
req.shouldReportPartialResults = true
var done = false
var words: [Int: (Double, Double, String)] = [:]     // по началу слова (в сотых секунды) — последнее, что распознано
var lastUpdate = Date()
rec.recognitionTask(with: req) { result, error in
    if let e = error { print("error:", e.localizedDescription); done = true; return }
    guard let r = result else { return }
    for s in r.bestTranscription.segments where s.duration > 0 { words[Int(s.timestamp * 100)] = (s.timestamp, s.duration, s.substring) }
    lastUpdate = Date()
    if r.isFinal { print("-- final:", r.bestTranscription.formattedString) }
}
let until = Date().addingTimeInterval(90)
while Date() < until && Date().timeIntervalSince(lastUpdate) < 12 { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
for k in words.keys.sorted() { let w = words[k]!; print(String(format: "%.2f %.2f %@", w.0, w.1, w.2)) }
