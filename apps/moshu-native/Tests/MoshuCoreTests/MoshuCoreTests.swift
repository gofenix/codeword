import Foundation
import Testing
@testable import MoshuCore

struct MoshuCoreTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func sm2GoldenSequenceAndFailure() {
        var r = Review(wordId: "one")
        r = r.scheduled(quality: 4, now: now)
        #expect(r.interval == 1 && r.repetitions == 1 && r.easiness == 250)
        #expect(r.firstReviewedAt == now)
        r = r.scheduled(quality: 4, now: now.addingTimeInterval(86400))
        #expect(r.interval == 6 && r.repetitions == 2)
        r = r.scheduled(quality: 3, now: now.addingTimeInterval(7 * 86400))
        #expect(r.interval == 14 && r.easiness == 236 && r.repetitions == 3)
        r = r.scheduled(quality: 0, now: now)
        #expect(r.interval == 0 && r.repetitions == 0 && r.easiness == 156 && r.dueAt == now)
        #expect(r.firstReviewedAt == self.now)
        r = r.scheduled(quality: 0, now: now)
        #expect(r.easiness == 130)
        for _ in 0..<30 { r = r.scheduled(quality: 5, now: now) }
        #expect(r.interval == 365 && r.easiness == 250)
    }

    @Test func legacyPrefixRuleKeepsCrossBookProgressWithoutResurfacing() {
        let crossBook = Word(id: "qwerty_linuxcommand_00001", word: "ab", translation: "测试工具", domain: "qwerty_coder")
        let new = Word(id: "new", word: "new", translation: "新")
        let removed = Word(id: "removed", word: "removed", translation: "移除")
        var s = UserState(); s.removed = [removed.id]
        s.reviews[crossBook.id] = Review(wordId: crossBook.id).scheduled(quality: 0, now: now)
        let queue = Learning.eligible(words: [new, removed, crossBook], state: s, now: now)
        #expect(queue.map(\.id) == [new.id])
        #expect(s.reviews[crossBook.id] != nil)
        #expect(Learning.vocabID(from: crossBook.id) == "qwerty_linuxcommand")
        #expect(Learning.eligible(words: [new], state: s, now: now).map(\.id) == [new.id])
    }

    @Test func preferencesAndQuestionUniqueness() {
        var p = Preferences()
        #expect(Learning.kinds(p) == [.meaning, .word])
        p.listeningEnabled = true; p.spellingEnabled = true
        #expect(Learning.kinds(p) == QuestionKind.allCases)
        p.learningMode = "swipe"
        #expect(Learning.kinds(p) == [.spelling])
        let words = [Word(id: "a", word: "Apple", translation: "苹果"), Word(id: "b", word: "banana", translation: "香蕉"), Word(id: "c", word: "alias", translation: "苹果"), Word(id: "d", word: "orange", translation: "橙子")]
        let q = Learning.question(words[0], kind: .meaning, pool: words)
        #expect(q.options.count == 4 && Set(q.options).count == 4)
        #expect(q.options[q.correctIndex] == "苹果")
        #expect(Learning.typedCorrect("  APPLE\n", word: words[0]))
        #expect(!Learning.typedCorrect("ap ple", word: words[0]))
    }

    @Test func swipeThresholdsMatchLegacy() {
        #expect(Learning.swipeQuality(milliseconds: 1000, review: nil) == 4)
        #expect(Learning.swipeQuality(milliseconds: 8000, review: nil) == 3)
        #expect(Learning.swipeQuality(milliseconds: 18000, review: nil) == 0)
        let familiar = Review(wordId: "a")
        #expect(Learning.swipeQuality(milliseconds: 2999, review: familiar) == 5)
        #expect(Learning.swipeQuality(milliseconds: 3000, review: familiar) == 4)
    }

    @Test func allBundledBooksLoadAndKeepCounts() throws {
        let books = try Catalog.books()
        #expect(books.count == 43)
        #expect(Set(books.map(\.id)).count == books.count)
        for book in books {
            let words = try Catalog.words(book.id)
            #expect(words.count == book.wordCount, "\(book.id) count")
            #expect(Set(words.map(\.id)).count == words.count, "\(book.id) IDs")
            #expect(words.allSatisfy { !$0.word.isEmpty && !$0.translation.isEmpty })
        }
    }

    @Test func atomicRoundTripAndCorruptionProtection() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskStore(directory: root)
        var s = UserState(); s.reviews["a"] = Review(wordId: "a").scheduled(quality: 4, now: now)
        s.favorites = ["a"]; s.activity = ["2026-01-01": 1]; s.preferences.spellingEnabled = true
        try disk.save(s)
        #expect(try disk.load() == s)
        let saved = try Data(contentsOf: disk.stateURL)
        var invalid = s; invalid.schemaVersion = 20
        #expect(throws: (any Error).self) { try disk.save(invalid) }
        #expect(try Data(contentsOf: disk.stateURL) == saved)
        try Data("{broken".utf8).write(to: disk.stateURL)
        #expect(throws: (any Error).self) { try disk.load() }
        #expect(try Data(contentsOf: disk.stateURL) == Data("{broken".utf8))
    }

    @Test func failedSaveCannotCreatePartialDocument() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("occupied".utf8).write(to: root)
        let disk = DiskStore(directory: root)
        #expect(throws: (any Error).self) { try disk.save(UserState()) }
        #expect(try Data(contentsOf: root) == Data("occupied".utf8))
    }

    @Test func legacyBackupBeforeImportAndIdempotentMerge() throws {
        let root = temporary(), source = temporary()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let disk = DiskStore(directory: root)
        var current = UserState(); current.activity = ["2026-10-25": 2]
        current.reviews["a"] = Review(wordId: "a").scheduled(quality: 4, now: now.addingTimeInterval(300))
        try disk.save(current)
        let raw = Data(#"{"a":{"wordId":"a","easiness":250,"interval":1,"repetitions":1,"dueAt":"2023-11-15T22:13:20.000","lastReviewedAt":"2023-11-14T22:13:20.000"}}"#.utf8)
        try raw.write(to: source.appendingPathComponent("codeword_review_state.json"))
        try Data(#"{"2026-10-25":4}"#.utf8).write(to: source.appendingPathComponent("codeword_activity.json"))
        try Data(#"{"schemaVersion":2,"favorites":["a"],"removed":["x"],"studyMinutes":{"2026-10-25":3},"selectedVocabId":"qwerty_coder"}"#.utf8).write(to: source.appendingPathComponent("codeword_user_data.json"))
        let plan = try disk.prepareLegacyImport(from: source)
        #expect(plan.incoming.reviews["a"]?.firstReviewedAt == Date(timeIntervalSince1970: 0))
        #expect(try Data(contentsOf: plan.backupURL.appendingPathComponent("codeword_review_state.json")) == raw)
        #expect(try disk.load() == current)
        #expect(try Data(contentsOf: source.appendingPathComponent("codeword_review_state.json")) == raw)
        let merged = DiskStore.merge(current, with: plan.incoming)
        #expect(merged.reviews["a"] == current.reviews["a"])
        #expect(merged.activity["2026-10-25"] == 4 && merged.studyMinutes["2026-10-25"] == 3)
        #expect(merged.favorites == ["a"] && merged.removed == ["x"])
        #expect(DiskStore.merge(merged, with: plan.incoming) == merged)
        #expect(try Data(contentsOf: plan.backupURL.appendingPathComponent("moshu-native.json")) == Codec.encoder().encode(current))
    }

    @Test func malformedLegacyIsBackedUpAndNeverApplied() throws {
        let root = temporary(), source = temporary()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let disk = DiskStore(directory: root)
        try disk.save(UserState())
        let before = try Data(contentsOf: disk.stateURL)
        let raw = Data("not-json".utf8)
        try raw.write(to: source.appendingPathComponent("codeword_review_state.json"))
        #expect(throws: (any Error).self) { try disk.prepareLegacyImport(from: source) }
        #expect(try Data(contentsOf: disk.stateURL) == before)
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0].appendingPathComponent("codeword_review_state.json")) == raw)
    }

    @Test func legacyFutureSchemaAndPendingClearRejected() throws {
        for raw in [#"{"schemaVersion":3}"#, #"{"schemaVersion":2,"pendingLearningDataClear":true}"#] {
            let root = temporary(), source = temporary()
            defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data(raw.utf8).write(to: source.appendingPathComponent("codeword_user_data.json"))
            #expect(throws: (any Error).self) { try DiskStore(directory: root).prepareLegacyImport(from: source) }
        }
    }

    @Test func completeFiveFileMigrationAndSubsecondDatesRoundTrip() throws {
        let root = temporary(), source = temporary()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let input: [String: String] = [
            "codeword_review_state.json": #"{"qwerty_coder_00001":{"wordId":"qwerty_coder_00001","easiness":236,"interval":6,"repetitions":2,"dueAt":"2026-10-26T12:00:00.123456+08:00","lastReviewedAt":"2026-10-25T12:00:00.123456+08:00","firstReviewedAt":"2026-10-20T12:00:00.123456+08:00"}}"#,
            "codeword_activity.json": #"{"2026-10-25":8}"#,
            "codeword_user_data.json": #"{"schemaVersion":2,"favorites":["qwerty_coder_00001"],"removed":["qwerty_coder_00002"],"selectedVocabId":"qwerty_python","openCounts":{"2026-10-25":3},"studyMinutes":{"2026-10-25":5}}"#,
            "codeword_learning_preferences.json": #"{"spellingEnabled":true,"listeningEnabled":true,"learningMode":"swipe"}"#,
            "codeword_articles.json": #"[{"id":"old-reading","createdAt":"2026-10-25T12:00:00.123456+08:00","articleText":"A saved reading.","vocabId":"qwerty_coder","wordPool":[{"word":"saved","translation":"保存"}]}]"#
        ]
        for (name, text) in input { try Data(text.utf8).write(to: source.appendingPathComponent(name)) }
        let disk = DiskStore(directory: root)
        let plan = try disk.prepareLegacyImport(from: source)
        #expect(plan.files.count == 5 && plan.incoming.selectedVocabId == "qwerty_python")
        #expect(plan.incoming.preferences.learningMode == "swipe" && plan.incoming.preferences.listeningEnabled)
        #expect(plan.incoming.articles.first?.translationText == "")
        #expect(plan.incoming.reviews["qwerty_coder_00001"]?.easiness == 236)
        let date = try #require(plan.incoming.reviews["qwerty_coder_00001"]?.lastReviewedAt)
        #expect(abs(date.timeIntervalSince1970 - floor(date.timeIntervalSince1970) - 0.123456) < 0.000001)
        let merged = DiskStore.merge(UserState(), with: plan.incoming)
        try disk.save(merged)
        #expect(try disk.load() == merged)
        for (name, text) in input {
            #expect(try Data(contentsOf: source.appendingPathComponent(name)) == Data(text.utf8))
            #expect(try Data(contentsOf: plan.backupURL.appendingPathComponent(name)) == Data(text.utf8))
        }
    }

    @Test func nativeExportHasNoSecretFieldAndCanRestore() throws {
        let root = temporary(), imported = temporary()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: imported) }
        var s = UserState(); s.ai.baseURL = "https://example.com/v1"; s.ai.model = "local-model"
        let data = try Codec.encoder().encode(s)
        #expect(!String(decoding: data, as: UTF8.self).contains("apiKey"))
        try data.write(to: imported)
        let plan = try DiskStore(directory: root).prepareNativeImport(from: imported)
        #expect(plan.incoming == s)
    }

    @Test func readingValidationAndEndpoints() throws {
        let valid = readingJSON
        #expect(try GeneratedReading.parse(valid).questions.count == 3)
        #expect(try GeneratedReading.parse("```json\n" + valid + "\n```").title == "Story")
        #expect(try GeneratedReading.parse(valid.replacingOccurrences(of: "\"correct\":0", with: "\"correct\":9")).questions.isEmpty)
        #expect(try GeneratedReading.parse("intro\n" + valid + "\nend").title == "Story")
        #expect(try GeneratedReading.parse("A plain article.").article == "A plain article.")
        #expect(throws: (any Error).self) { try GeneratedReading.parse(#"{"article":""}"#) }
        #expect(try ReadingClient.endpoint("https://example.com/v1/", path: "chat/completions").absoluteString == "https://example.com/v1/chat/completions")
        #expect(try ReadingClient.endpoint("http://localhost:11434/v1", path: "models").host == "localhost")
        for url in ["http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?key=secret", "file:///tmp/foo"] {
            #expect(throws: (any Error).self) { try ReadingClient.endpoint(url, path: "models") }
        }
    }

    private var readingJSON: String {
        #"{"title":"Story","article":"apple banana orange","translation":"苹果香蕉橙子","questions":[{"q":"一","options":["a","b","c","d"],"correct":0},{"q":"二","options":["a","b","c","d"],"correct":0},{"q":"三","options":["a","b","c","d"],"correct":0}]}"#
    }

    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("moshu-test-" + UUID().uuidString) }
}
