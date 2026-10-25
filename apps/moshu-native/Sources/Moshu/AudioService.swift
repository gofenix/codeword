import AVFoundation
import CryptoKit
import Foundation
import MoshuCore

@MainActor @Observable
final class AudioService {
    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private let directory: URL
    private var generation = 0
    private(set) var busy = false

    init(directory: URL) { self.directory = directory }

    func stop() { generation += 1; player?.stop(); speech.stopSpeaking(at: .immediate); busy = false }

    func speak(_ text: String, accent: String, system: Bool) async throws {
        stop()
        if system {
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: accent == "uk" ? "en-GB" : "en-US")
            u.rate = 0.42
            speech.speak(u)
            return
        }
        let token = generation
        busy = true
        defer { if token == generation { busy = false } }
        let hash = SHA256.hash(data: Data("\(accent):\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(hash + ".mp3")
        let bytes: Data
        if FileManager.default.fileExists(atPath: file.path) { bytes = try Data(contentsOf: file) }
        else {
            var c = URLComponents(string: "https://dict.youdao.com/dictvoice")!
            c.queryItems = [URLQueryItem(name: "audio", value: text), URLQueryItem(name: "type", value: accent == "uk" ? "1" : "2")]
            var request = URLRequest(url: c.url!); request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.value(forHTTPHeaderField: "Content-Type")?.contains("audio") == true,
                  !data.isEmpty, data.count < 2_000_000 else { throw MoshuError.message("音频服务响应无效。") }
            try Task.checkCancellation()
            guard token == generation else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            bytes = data
        }
        guard token == generation else { return }
        player = try AVAudioPlayer(data: bytes)
        guard player?.play() == true else { throw MoshuError.message("音频播放失败。") }
    }
}
