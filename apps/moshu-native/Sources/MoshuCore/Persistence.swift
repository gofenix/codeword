import Foundation

public struct ImportPlan: Identifiable, Sendable {
    public let incoming: UserState
    public let backupURL: URL
    public let files: [String]
    public var id: URL { backupURL }
}

/// One atomic document is the commit boundary for the native application.
/// All UI mutations use a candidate copy and publish only after the write succeeds.
public struct DiskStore: Sendable {
    public let directory: URL
    public var stateURL: URL { directory.appendingPathComponent("moshu-native.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> UserState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return UserState() }
        let s = try Codec.decoder().decode(UserState.self, from: Data(contentsOf: stateURL))
        try Self.validate(s)
        return s
    }

    public func save(_ state: UserState) throws {
        try Self.validate(state)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Codec.encoder().encode(state).write(to: stateURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    public func backup() throws -> URL {
        let url = directory.appendingPathComponent("Backups/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.copyItem(at: stateURL, to: url.appendingPathComponent("moshu-native.json"))
        }
        return url
    }

    public static func validate(_ s: UserState) throws {
        guard s.schemaVersion == 1 else { throw MoshuError.message("此备份的数据版本高于当前应用，请先升级应用。") }
        for (key, r) in s.reviews {
            guard key == r.wordId, (130...250).contains(r.easiness), (0...365).contains(r.interval), r.repetitions >= 0 else {
                throw MoshuError.message("学习进度包含无效记录，未修改当前数据。")
            }
        }
        for map in [s.activity, s.studyMinutes, s.openCounts] {
            guard map.values.allSatisfy({ $0 >= 0 }) else { throw MoshuError.message("统计中存在负数，未修改当前数据。") }
        }
        guard ["quiz", "swipe"].contains(s.preferences.learningMode) else { throw MoshuError.message("未知学习模式。") }
        for a in s.articles {
            guard !a.articleText.isEmpty, (a.questions ?? []).allSatisfy({ $0.options.count == 4 && (0..<4).contains($0.correct) }) else {
                throw MoshuError.message("阅读内容或题目格式无效，未修改当前数据。")
            }
        }
    }

    /// Copies known non-secret files first. The Flutter directory is never written to.
    public func prepareLegacyImport(from source: URL) throws -> ImportPlan {
        let names = ["codeword_review_state.json", "codeword_activity.json", "codeword_user_data.json", "codeword_learning_preferences.json", "codeword_articles.json"]
        let present = names.filter { FileManager.default.fileExists(atPath: source.appendingPathComponent($0).path) }
        guard !present.isEmpty else { throw MoshuError.message("所选文件夹中没有墨书 JSON 数据。请选择旧版文档目录。") }
        let backupURL = try backup()
        for name in present {
            let file = source.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 50_000_000 else {
                throw MoshuError.message("导入文件过大或为符号链接，未导入。")
            }
            try FileManager.default.copyItem(at: file, to: backupURL.appendingPathComponent(name))
        }
        func data(_ name: String) throws -> Data? {
            guard present.contains(name) else { return nil }
            return try Data(contentsOf: backupURL.appendingPathComponent(name))
        }
        var s = UserState()
        let d = Codec.decoder()
        if let bytes = try data("codeword_review_state.json") {
            // Legacy firstReviewedAt was added later; preserve its epoch fallback.
            var object = try JSONSerialization.jsonObject(with: bytes) as? [String: [String: Any]]
            guard object != nil else { throw MoshuError.message("旧进度 JSON 结构无效。") }
            for key in object!.keys {
                if object![key]?["firstReviewedAt"] == nil || object![key]?["firstReviewedAt"] is NSNull {
                    if let last = object![key]?["lastReviewedAt"], !(last is NSNull) {
                        object![key]?["firstReviewedAt"] = "1970-01-01T00:00:00Z"
                    }
                }
            }
            s.reviews = try d.decode([String: Review].self, from: JSONSerialization.data(withJSONObject: object!))
        }
        if let bytes = try data("codeword_activity.json") { s.activity = try d.decode([String: Int].self, from: bytes) }
        if let bytes = try data("codeword_user_data.json") {
            struct LegacyUser: Decodable {
                let schemaVersion: Int?
                let favorites: Set<String>?
                let removed: Set<String>?
                let openCounts: [String: Int]?
                let studyMinutes: [String: Int]?
                let selectedVocabId: String?
                let pendingLearningDataClear: Bool?
            }
            let u = try d.decode(LegacyUser.self, from: bytes)
            guard (u.schemaVersion ?? 0) <= 2, u.pendingLearningDataClear != true else {
                throw MoshuError.message("旧数据版本不兼容或存在未完成的清理操作，请先在旧版修复后重新导入。")
            }
            s.favorites = u.favorites ?? []; s.removed = u.removed ?? []
            s.openCounts = u.openCounts ?? [:]; s.studyMinutes = u.studyMinutes ?? [:]
            s.selectedVocabId = u.selectedVocabId ?? s.selectedVocabId
        }
        if let bytes = try data("codeword_learning_preferences.json") { s.preferences = try d.decode(Preferences.self, from: bytes) }
        if let bytes = try data("codeword_articles.json") { s.articles = try d.decode([Article].self, from: bytes) }
        try Self.validate(s)
        return ImportPlan(incoming: s, backupURL: backupURL, files: present)
    }

    public func prepareNativeImport(from source: URL) throws -> ImportPlan {
        let backupURL = try backup()
        let target = backupURL.appendingPathComponent("imported-native.json")
        try FileManager.default.copyItem(at: source, to: target)
        let incoming = try Codec.decoder().decode(UserState.self, from: Data(contentsOf: target))
        try Self.validate(incoming)
        return ImportPlan(incoming: incoming, backupURL: backupURL, files: [source.lastPathComponent])
    }

    /// Re-imports are idempotent: use latest review, maximum daily aggregates,
    /// union of collections and article IDs. Never infer a book from a word ID:
    /// merged books have cross-book IDs. Legacy queue prefix rules stay intact.
    public static func merge(_ current: UserState, with incoming: UserState) -> UserState {
        var result = current
        for (id, review) in incoming.reviews {
            if let old = result.reviews[id], (old.lastReviewedAt ?? .distantPast) >= (review.lastReviewedAt ?? .distantPast) { continue }
            result.reviews[id] = review
        }
        result.activity.merge(incoming.activity, uniquingKeysWith: max)
        result.studyMinutes.merge(incoming.studyMinutes, uniquingKeysWith: max)
        result.openCounts.merge(incoming.openCounts, uniquingKeysWith: max)
        result.favorites.formUnion(incoming.favorites); result.removed.formUnion(incoming.removed)
        result.selectedVocabId = incoming.selectedVocabId
        result.preferences = incoming.preferences
        let combined = Dictionary((current.articles + incoming.articles).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        result.articles = Array(combined.values.sorted { $0.createdAt > $1.createdAt }.prefix(20))
        return result
    }
}
