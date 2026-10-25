import Foundation

public struct Book: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let emoji: String
    public let wordCount: Int
    public let category: String
}

public struct Word: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let word: String
    public let phonetic: String
    public let pos: String
    public let translation: String
    public let translations: [String]
    public let exampleEn: String
    public let exampleCn: String
    public let domain: String
    public let level: String
    public let synonyms: [String]
    public let antonyms: [String]

    public init(id: String, word: String, translation: String, domain: String = "test") {
        self.id = id; self.word = word; self.translation = translation; self.domain = domain
        phonetic = ""; pos = ""; translations = [translation]; exampleEn = ""; exampleCn = ""
        level = ""; synonyms = []; antonyms = []
    }

    enum CodingKeys: String, CodingKey {
        case id, word, phonetic, pos, translation, translations, exampleEn, exampleCn, domain, level, synonyms, antonyms
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        word = try c.decode(String.self, forKey: .word)
        translation = try c.decode(String.self, forKey: .translation)
        phonetic = try c.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? ""
        translations = try c.decodeIfPresent([String].self, forKey: .translations) ?? [translation]
        exampleEn = try c.decodeIfPresent(String.self, forKey: .exampleEn) ?? ""
        exampleCn = try c.decodeIfPresent(String.self, forKey: .exampleCn) ?? ""
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? ""
        synonyms = try c.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        antonyms = try c.decodeIfPresent([String].self, forKey: .antonyms) ?? []
    }
}

public struct Review: Codable, Hashable, Sendable {
    public var wordId: String
    public var easiness = 250
    public var interval = 0
    public var repetitions = 0
    public var dueAt: Date?
    public var lastReviewedAt: Date?
    public var firstReviewedAt: Date?

    public init(wordId: String) { self.wordId = wordId }

    public func scheduled(quality: Int, now: Date) -> Review {
        precondition((0...5).contains(quality))
        var r = self
        let diff = Double(5 - quality)
        r.easiness = Int((min(2.5, max(1.3, Double(easiness) / 100 + 0.1 - diff * (0.08 + diff * 0.02))) * 100).rounded())
        if quality < 3 { r.repetitions = 0; r.interval = 0 }
        else {
            r.repetitions += 1
            r.interval = r.repetitions == 1 ? 1 : r.repetitions == 2 ? 6 : min(365, max(1, Int((Double(interval * r.easiness) / 100).rounded())))
        }
        r.dueAt = now.addingTimeInterval(Double(r.interval) * 86400)
        r.lastReviewedAt = now
        r.firstReviewedAt = firstReviewedAt ?? now
        return r
    }

    public var mastery: String {
        if lastReviewedAt == nil { return "待学习" }
        if repetitions == 0 { return "陌生" }
        if easiness >= 250 && repetitions >= 3 { return "熟悉" }
        if easiness >= 230 && repetitions >= 2 { return "认识" }
        return "模糊"
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var spellingEnabled = false
    public var listeningEnabled = false
    public var learningMode = "quiz"
    public init() {}
}

public struct AISettings: Codable, Equatable, Sendable {
    public var baseURL = "https://api.minimaxi.com/anthropic"
    public var model = "MiniMax-M2.7"
    public var isLocal: Bool { ["localhost", "127.0.0.1", "::1", "[::1]"].contains(URLComponents(string: baseURL)?.host ?? "") }
    public init() {}
}

public struct ReadingQuestion: Codable, Hashable, Sendable {
    public let q: String
    public let options: [String]
    public let correct: Int
    public init(q: String, options: [String], correct: Int) {
        self.q = q; self.options = options; self.correct = correct
    }
}

public struct Article: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var createdAt: Date
    public var title: String
    public var articleText: String
    public var translationText: String
    public var level: String
    public var vocabId: String
    public var vocabName: String
    public var wordPool: [[String: String]]
    public var questions: [ReadingQuestion]?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, title, articleText, translationText, level, vocabId, vocabName, wordPool, questions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        articleText = try c.decode(String.self, forKey: .articleText)
        translationText = try c.decodeIfPresent(String.self, forKey: .translationText) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? ""
        vocabId = try c.decode(String.self, forKey: .vocabId)
        vocabName = try c.decodeIfPresent(String.self, forKey: .vocabName) ?? ""
        wordPool = try c.decode([[String: String]].self, forKey: .wordPool)
        questions = try c.decodeIfPresent([ReadingQuestion].self, forKey: .questions)
    }

    public init(title: String, text: String, translation: String, book: Book, words: [Word], questions: [ReadingQuestion]) {
        id = UUID().uuidString; createdAt = Date(); self.title = title
        articleText = text; translationText = translation
        level = words.map(\.level).first { ["A1", "A2", "B1", "B2", "C1", "C2"].contains($0) } ?? "B1"
        vocabId = book.id; vocabName = book.name
        wordPool = words.map { ["id": $0.id, "word": $0.word, "translation": $0.translation, "vocabId": book.id, "level": $0.level] }
        self.questions = questions
    }
}

public struct UserState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var reviews: [String: Review] = [:]
    public var activity: [String: Int] = [:]
    public var favorites: Set<String> = []
    public var removed: Set<String> = []
    public var openCounts: [String: Int] = [:]
    public var studyMinutes: [String: Int] = [:]
    public var selectedVocabId = "qwerty_coder"
    public var preferences = Preferences()
    public var ai = AISettings()
    public var appearance = "system"
    public var accent = "us"
    public var articles: [Article] = []
    public init() {}
}

public enum MoshuError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

public enum Codec {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            // Native schema stores exact Foundation reference seconds. Accept
            // legacy ISO strings independently, including local Dart dates.
            if let seconds = try? c.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            let raw = try c.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) { return date }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: raw) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: raw) { return date }
            // Dart's local DateTime.toIso8601String() has no UTC offset.
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = .current
            let parts = raw.split(separator: ".", maxSplits: 1)
            if parts.count == 2, parts[1].allSatisfy(\.isNumber) {
                local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                if let base = local.date(from: String(parts[0])), let fraction = Double("0." + parts[1]) {
                    return base.addingTimeInterval(fraction)
                }
            }
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
                local.dateFormat = format
                if let date = local.date(from: raw) { return date }
            }
            throw MoshuError.message("日期格式无法识别，未导入数据。")
        }
        return d
    }
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .deferredToDate
        return e
    }
    public static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

public enum Catalog {
    public static func books() throws -> [Book] { try Codec.decoder().decode([Book].self, from: data("_qwerty_index")) }
    public static func words(_ id: String) throws -> [Word] {
        guard !id.contains("/"), !id.contains("..") else { throw MoshuError.message("词书 ID 无效。") }
        return try Codec.decoder().decode([Word].self, from: data(id))
    }
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources/vocab") else {
            throw MoshuError.message("词书资源缺失：\(name)。请重新构建完整应用包。")
        }
        return try Data(contentsOf: url)
    }
    public static var noticesURL: URL? { Bundle.module.url(forResource: "THIRD-PARTY", withExtension: "txt", subdirectory: "Resources") }
}
