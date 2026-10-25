import Foundation
import Testing
@testable import MoshuCore

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        let anthropic = request.url!.path.hasSuffix("messages")
        if anthropic {
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "fake-test-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        } else { #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-key") }
        var status = 200
        var body = "{\"data\":[]}"
        if host == "failed.test" { status = 401; body = "server must not echo fake-test-key" }
        else if request.url!.path.hasSuffix("chat/completions") || anthropic {
            #expect(request.httpMethod == "POST")
            let reading: [String: Any] = [
                "title": "Story", "article": host == "missing.test" ? "apple only" : "apple banana orange in a story.", "translation": "水果故事",
                "questions": (0..<3).map { ["q": "问题\($0)", "options": ["a", "b", "c", "d"], "correct": 0] as [String: Any] }
            ]
            let content = String(decoding: try! JSONSerialization.data(withJSONObject: reading), as: UTF8.self)
            let envelope: [String: Any] = anthropic ? ["content": [["type": "thinking", "thinking": "must be ignored"], ["type": "text", "text": content]]] : ["choices": [["message": ["content": content]]]]
            body = String(decoding: try! JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct ReadingTransportTests {
    private func client() -> ReadingClient {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockProtocol.self]
        return ReadingClient(session: URLSession(configuration: c))
    }
    private func config(_ host: String) -> AISettings {
        var s = AISettings(); s.baseURL = "https://\(host)/v1"; s.model = "test-model"; return s
    }
    private var words: [Word] { ["apple", "banana", "orange"].map { Word(id: $0, word: $0, translation: "水果") } }

    @Test func generationAndConnectionUseMockOnly() async throws {
        let client = client()
        try await client.verify(settings: config("ok.test"), key: "fake-test-key")
        let generated = try await client.generate(settings: config("ok.test"), key: "fake-test-key", words: words, theme: "fruit")
        #expect(generated.title == "Story" && generated.questions.count == 3)
    }

    @Test func providerErrorDoesNotExposeResponseOrKey() async throws {
        do {
            try await client().verify(settings: config("failed.test"), key: "fake-test-key")
            Issue.record("Expected HTTP failure")
        } catch {
            #expect(error.localizedDescription.contains("401"))
            #expect(!error.localizedDescription.contains("fake-test-key"))
        }
    }

    @Test func anthropicMessagesProtocolIgnoresReasoningBlocks() async throws {
        var settings = config("anthropic.test"); settings.baseURL += "/anthropic"
        let generated = try await client().generate(settings: settings, key: "fake-test-key", words: words, theme: "fruit")
        #expect(generated.title == "Story")
        #expect(!generated.article.contains("must be ignored"))
    }

    @Test func cancelledRequestCannotProduceReading() async {
        let task = Task {
            try Task.checkCancellation()
            return try await client().generate(settings: config("ok.test"), key: "fake-test-key", words: words, theme: "fruit")
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation must throw") }
        catch {}
    }
}
