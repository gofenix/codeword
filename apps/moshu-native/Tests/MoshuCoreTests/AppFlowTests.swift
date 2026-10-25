import Foundation
import Testing
import MoshuCore
@testable import Moshu

@MainActor struct AppFlowTests {
    @Test func wrongRetryAndBackNeverDoubleCount() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(directory: root, audioEnabled: false)
        let session = LearningSession(model: model)
        let first = try #require(session.current)
        session.answer(0)
        #expect(session.wrong)
        #expect(model.state.reviews[first.word.id]?.repetitions == 0)
        session.continueAfterWrong()
        let retryIndex = try #require(session.questions.firstIndex { $0.word.id == first.word.id && $0.retry })
        let retry = session.questions[retryIndex]
        #expect(retry.kind != first.kind)
        while session.index < retryIndex { session.answer(4) }
        let before = model.state
        session.answer(3)
        #expect(model.state == before)
        session.back()
        session.answer(4, objective: false)
        #expect(model.state == before)
        #expect(try model.disk.load() == model.state)
    }

    @Test func queueRefillsBeyondFirstSixteenAndModesStayValid() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(directory: root, audioEnabled: false)
        let session = LearningSession(model: model)
        #expect(session.questions.count == 16)
        for _ in 0..<25 { session.answer(4) }
        #expect(!session.finished && session.scored.count == 25)
        #expect(model.state.activity[Codec.dayKey(Date())] == 25)
        model.commit { $0.preferences.learningMode = "swipe" }
        let currentID = session.current?.id
        session.preferencesChanged()
        #expect(session.current?.id == currentID && session.previousMode == "swipe")
        model.commit { $0.preferences.learningMode = "quiz"; $0.preferences.spellingEnabled = true; $0.preferences.listeningEnabled = true }
        session.preferencesChanged()
        for q in session.questions.dropFirst(session.index) {
            #expect(q.kind == .spelling || q.options.count == 4)
        }
    }

    @Test func saveFailureDoesNotAdvanceOrPublishAnswer() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(directory: root, audioEnabled: false)
        let session = LearningSession(model: model)
        let before = model.state
        try FileManager.default.removeItem(at: root)
        try Data("not-a-directory".utf8).write(to: root)
        session.answer(4)
        #expect(model.state == before && session.index == 0 && session.scored.isEmpty)
        #expect(model.error != nil)
    }

    @Test func clearIsAtomicBackedUpAndKeepsConfiguration() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(directory: root, audioEnabled: false)
        let session = LearningSession(model: model); session.answer(4)
        model.commit { $0.preferences.spellingEnabled = true; $0.ai.baseURL = "http://localhost:11434/v1"; $0.ai.model = "test"; $0.favorites.insert("one"); $0.removed.insert("two") }
        let before = model.state
        model.clearLearning()
        #expect(model.state.reviews.isEmpty && model.state.activity.isEmpty && model.state.favorites.isEmpty && model.state.removed.isEmpty)
        #expect(model.state.ai == before.ai && model.state.preferences == before.preferences && model.state.selectedVocabId == before.selectedVocabId)
        #expect(try model.disk.load() == model.state)
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        let backup = try Codec.decoder().decode(UserState.self, from: Data(contentsOf: backups[0].appendingPathComponent("moshu-native.json")))
        #expect(backup == before)
    }

    @Test func corruptLaunchRemainsReadOnly() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stateURL = root.appendingPathComponent("moshu-native.json")
        let raw = Data("{damaged".utf8); try raw.write(to: stateURL)
        let model = AppModel(directory: root, audioEnabled: false)
        #expect(model.locked && model.error != nil)
        #expect(model.books.count == 43)
        #expect(!model.commit { $0.favorites.insert("one") })
        #expect(try Data(contentsOf: stateURL) == raw)
    }

    @Test func keychainFakeKeyIsIsolatedByEndpoint() throws {
        // A unique test account: never load or clear any user's configured key.
        let endpoint = "https://moshu-keychain-test.invalid/" + UUID().uuidString
        defer { try? Keychain.delete(for: endpoint) }
        try Keychain.save("fake-key-for-local-testing-only", for: endpoint)
        #expect(Keychain.contains(for: endpoint))
        #expect(try Keychain.load(for: endpoint) == "fake-key-for-local-testing-only")
        #expect(try Keychain.load(for: endpoint + "/other-provider").isEmpty)
        try Keychain.delete(for: endpoint)
        #expect(!Keychain.contains(for: endpoint))
    }

    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("moshu-app-test-" + UUID().uuidString) }
}
