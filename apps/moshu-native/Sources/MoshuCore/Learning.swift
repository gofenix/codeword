import Foundation

public enum QuestionKind: String, CaseIterable, Sendable {
    case meaning, word, listening, spelling
    public var label: String {
        switch self {
        case .meaning: "看单词选释义"
        case .word: "看释义选单词"
        case .listening: "听音选释义"
        case .spelling: "看释义拼写"
        }
    }
}

public struct Question: Identifiable, Sendable {
    public let id = UUID()
    public let word: Word
    public let kind: QuestionKind
    public let options: [String]
    public let correctIndex: Int
    public let retry: Bool
}

public enum Learning {
    public static func vocabID(from wordID: String) -> String {
        let parts = wordID.split(separator: "_")
        guard parts.count >= 3, parts[0] == "qwerty" else { return wordID }
        return parts.dropLast().joined(separator: "_")
    }

    public static func eligible(words: [Word], state: UserState, now: Date = Date(), limit: Int = 16) -> [Word] {
        let available = words.filter { !state.removed.contains($0.id) }
        let due = available.filter { vocabID(from: $0.id) == state.selectedVocabId && (state.reviews[$0.id]?.dueAt ?? .distantFuture) <= now }
            .sorted { (state.reviews[$0.id]?.dueAt ?? .distantFuture) < (state.reviews[$1.id]?.dueAt ?? .distantFuture) }
        let new = available.filter { state.reviews[$0.id] == nil }
        return Array((due + new).prefix(limit))
    }

    public static func kinds(_ p: Preferences) -> [QuestionKind] {
        if p.learningMode == "swipe" { return [.spelling] }
        return [.meaning, .word] + (p.listeningEnabled ? [.listening] : []) + (p.spellingEnabled ? [.spelling] : [])
    }

    public static func question(_ word: Word, kind: QuestionKind, pool: [Word], retry: Bool = false) -> Question {
        if kind == .spelling { return Question(word: word, kind: kind, options: [], correctIndex: 0, retry: retry) }
        let useWord = kind == .word
        let correct = useWord ? word.word : compactMeaning(word.translation)
        var seen: Set<String> = [correct.lowercased()]
        var best: [(String, Int)] = []
        for other in pool where other.id != word.id {
            let value = useWord ? other.word : compactMeaning(other.translation)
            guard !value.isEmpty, !seen.contains(value.lowercased()) else { continue }
            if useWord && best.count == 3 && abs(word.word.count - value.count) >= best.last!.1 { continue }
            let score = useWord ? editDistance(word.word.lowercased(), value.lowercased()) : (word.pos == other.pos ? 0 : 80) + abs(correct.count - value.count)
            if best.count < 3 || score < best.last!.1 {
                best.append((value, score)); best.sort { $0.1 < $1.1 }
                if best.count > 3 { let removed = best.removeLast(); seen.remove(removed.0.lowercased()) }
                seen.insert(value.lowercased())
            }
        }
        var options = [correct] + best.map(\.0)
        for value in useWord ? ["example", "language", "system", "different"] : ["示例", "语言", "系统", "不同的"] where options.count < 4 {
            if seen.insert(value.lowercased()).inserted { options.append(value) }
        }
        options.shuffle()
        return Question(word: word, kind: kind, options: options, correctIndex: options.firstIndex(of: correct)!, retry: retry)
    }

    public static func compactMeaning(_ raw: String) -> String {
        let first = raw.components(separatedBy: "【")[0].components(separatedBy: CharacterSet(charactersIn: ";；"))[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return first.count > 48 ? String(first.prefix(47)) + "…" : first
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var previous = Array(0...y.count)
        for i in x.indices {
            var current = [i + 1]
            for j in y.indices { current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (x[i] == y[j] ? 0 : 1))) }
            previous = current
        }
        return previous.last!
    }

    public static func typedCorrect(_ answer: String, word: Word) -> Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == word.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func swipeQuality(milliseconds: Int, review: Review?) -> Int {
        let familiar = review.map { $0.repetitions >= 2 || $0.easiness >= 230 } ?? false
        if familiar && milliseconds < 3000 { return 5 }
        if milliseconds < 8000 { return 4 }
        if milliseconds < 18000 { return 3 }
        return 0
    }
}
