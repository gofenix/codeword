import SwiftUI
import MoshuCore
import Security
import LocalAuthentication

@MainActor @Observable
final class AppModel {
    var state = UserState()
    var books: [Book] = []
    var words: [Word] = []
    var error: String?
    var notice: String?
    var locked = false
    var loading = false
    var dataGeneration = 0
    var audioMessage: String?
    var destination: Destination? = .learn
    var keyStored = false
    let disk: DiskStore
    let audio: AudioService
    private let audioEnabled: Bool

    init(directory: URL? = nil, audioEnabled: Bool = true) {
        self.audioEnabled = audioEnabled && ProcessInfo.processInfo.environment["MOSHU_DISABLE_AUDIO_NETWORK"] != "1"
        let root = directory ?? ProcessInfo.processInfo.environment["MOSHU_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.applicationSupportDirectory.appendingPathComponent("com.codeword.moshu.native", isDirectory: true)
        disk = DiskStore(directory: root)
        audio = AudioService(directory: root.appendingPathComponent("Audio", isDirectory: true))
        do {
            state = try disk.load()
            keyStored = Keychain.contains(for: state.ai.baseURL)
        } catch {
            locked = true
            self.error = "无法读取学习数据。为保护原文件，写入已暂停。请导出备份或修复后重新启动。\n\(error.localizedDescription)"
        }
        do {
            books = try Catalog.books()
            if !books.contains(where: { $0.id == state.selectedVocabId }) {
                // Keep unknown legacy IDs in storage; fall back only for display.
                notice = "原词书不在当前目录中，进度已保留。请在词书页选择词书。"
            }
            words = try Catalog.words(book?.id ?? "qwerty_coder")
            if !locked { commit { $0.openCounts[Codec.dayKey(Date()), default: 0] += 1 } }
        } catch {
            locked = true
            self.error = "无法读取数据或词书。为保护原文件，写入已暂停。请导出备份或修复后重新启动。\n\(error.localizedDescription)"
        }
    }

    var book: Book? { books.first { $0.id == state.selectedVocabId } ?? books.first }
    var available: [Word] { words.filter { !state.removed.contains($0.id) } }
    var learned: [Word] { available.filter { state.reviews[$0.id]?.lastReviewedAt != nil } }
    var due: [Word] { available.filter { Learning.vocabID(from: $0.id) == state.selectedVocabId && (state.reviews[$0.id]?.dueAt ?? .distantFuture) <= Date() } }
    var todayCount: Int { state.activity[Codec.dayKey(Date()), default: 0] }
    var aiConfigured: Bool { !state.ai.baseURL.isEmpty && !state.ai.model.isEmpty && (state.ai.isLocal || keyStored) }

    @discardableResult
    func commit(_ edit: (inout UserState) -> Void) -> Bool {
        guard !locked else { error = "数据保护模式下不能写入。请先修复数据文件并重新启动。"; return false }
        var candidate = state
        edit(&candidate)
        do { try disk.save(candidate); state = candidate; return true }
        catch { self.error = "保存失败，本次操作未提交。\(error.localizedDescription)"; return false }
    }

    func select(_ book: Book) {
        do {
            let loaded = try Catalog.words(book.id)
            if commit({ $0.selectedVocabId = book.id }) { words = loaded; destination = .learn }
        } catch { self.error = error.localizedDescription }
    }

    func favorite(_ id: String) {
        commit { if $0.favorites.contains(id) { $0.favorites.remove(id) } else { $0.favorites.insert(id) } }
    }

    func remove(_ id: String) {
        commit { $0.removed.insert(id) }
    }

    func applyImport(_ plan: ImportPlan) {
        if commit({ $0 = DiskStore.merge($0, with: plan.incoming) }) {
            dataGeneration += 1
            do { words = try Catalog.words(book?.id ?? "qwerty_coder") } catch { self.error = error.localizedDescription }
            notice = "导入完成。原始文件和导入前进度已备份，重复导入不会累加统计。"
        }
    }

    func clearLearning() {
        do {
            _ = try disk.backup()
            if commit({
                $0.reviews = [:]; $0.activity = [:]; $0.studyMinutes = [:]; $0.favorites = []; $0.removed = []
                $0.openCounts = [:]; $0.articles = []
            }) { dataGeneration += 1; notice = "学习数据已清理，清理前备份已保留。" }
        } catch { self.error = "备份失败，未清理数据。" }
    }

    func speak(_ word: Word, system: Bool = false) {
        guard audioEnabled else { return }
        Task {
            do { try await audio.speak(word.word, accent: state.accent, system: system) }
            catch is CancellationError {}
            catch { self.audioMessage = "词音暂不可用，可改用系统朗读；学习进度不受影响。" }
        }
    }
}

enum Keychain {
    private static let service = "com.codeword.moshu.native.ai"
    private static func query(_ baseURL: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let baseURL { q[kSecAttrAccount as String] = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return q
    }
    static func load(for baseURL: String) throws -> String {
        var q = query(baseURL)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw MoshuError.message("无法访问钥匙串，请检查系统授权。")
        }
        return value
    }
    static func contains(for baseURL: String) -> Bool {
        var q = query(baseURL)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    static func save(_ value: String, for baseURL: String) throws {
        if value.isEmpty { try clear(); return }
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query(baseURL) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(baseURL)
            q[kSecValueData as String] = Data(value.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw MoshuError.message("密钥保存失败。") }
        } else if status != errSecSuccess { throw MoshuError.message("密钥保存失败。") }
    }
    static func clear() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MoshuError.message("删除密钥失败。") }
    }
    static func delete(for baseURL: String) throws {
        let status = SecItemDelete(query(baseURL) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MoshuError.message("删除密钥失败。") }
    }
}
