import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MoshuCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var baseURL = ""
    @State private var aiModel = ""
    @State private var newKey = ""
    @State private var verifyTask: Task<Void, Never>?
    @State private var checking = false
    @State private var checkMessage = ""
    @State private var plan: ImportPlan?
    @State private var clearConfirmation = false
    @State private var deleteAIConfirmation = false

    var body: some View {
        Form {
            Section("学习") {
                Toggle("听音选释义", isOn: setting(\.preferences.listeningEnabled))
                Toggle("看释义拼写", isOn: setting(\.preferences.spellingEnabled))
            }
            Section("AI 阅读 · 自备服务") {
                Label(model.aiConfigured ? "已配置 · 密钥保存在钥匙串" : "未配置", systemImage: model.aiConfigured ? "checkmark.shield" : "key")
                Menu("填入服务地址") {
                    Button("MiniMax") { baseURL = "https://api.minimaxi.com/anthropic"; aiModel = "MiniMax-M2.7" }
                    Button("OpenAI") { baseURL = "https://api.openai.com/v1"; aiModel = "gpt-5-mini" }
                    Button("OpenRouter") { baseURL = "https://openrouter.ai/api/v1"; aiModel = "openrouter/auto" }
                    Button("DeepSeek") { baseURL = "https://api.deepseek.com/v1"; aiModel = "deepseek-v4-flash" }
                    Button("智谱 BigModel") { baseURL = "https://open.bigmodel.cn/api/paas/v4"; aiModel = "glm-4.6" }
                    Button("月之暗面 Moonshot") { baseURL = "https://api.moonshot.cn/v1"; aiModel = "kimi-k2.5" }
                    Button("本机 Ollama") { baseURL = "http://localhost:11434/v1"; aiModel = "llama3.2" }
                    Button("自定义") { baseURL = ""; aiModel = "" }
                }
                TextField("Base URL", text: $baseURL)
                TextField("模型 ID", text: $aiModel)
                SecureField("新 API Key（留空保留已存密钥）", text: $newKey)
                Text("密钥仅保存到 macOS 钥匙串。本机模型可不填 Key。修改服务地址时请同时填入对应密钥，或先删除原配置。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存配置") { saveAI() }.disabled(checking)
                    Button(checking ? "测试中…" : "测试连接（模型目录）") { verify() }.disabled(checking)
                    if checking { Button("取消") { verifyTask?.cancel(); checking = false } }
                    Spacer()
                    Button("删除 AI 配置", role: .destructive) { deleteAIConfirmation = true }
                }
                if !checkMessage.isEmpty { Text(checkMessage).font(.caption).foregroundStyle(.secondary) }
                Text("仅点击生成时会把所选单词发送给此服务。模型费用由服务商收取。测试连接也会发送凭据，请确认地址。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本地数据") {
                HStack {
                    Button("导入旧版墨书文件夹…") { chooseLegacy() }
                    Button("导入原生备份…") { chooseNative() }
                }
                HStack {
                    Button("导出原生备份…") { export() }
                    Button("查看备份文件夹") { NSWorkspace.shared.open(model.disk.directory.appendingPathComponent("Backups")) }
                    Spacer()
                    Button("清理学习数据…", role: .destructive) { clearConfirmation = true }
                }
                Text("导入前先备份已知旧文件与当前进度。合并保留较新的复习状态，统计取每日最大值；原文件不会被修改，API Key 不参与导入或导出。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("关于墨书") {
                Text("墨书 · 本地优先背单词")
                LabeledContent("版本", value: "1.0.0 · SwiftUI 原生预览")
                Text("macOS 26 及以上 · 无账号 · 数据保存在本机")
                Button("词书来源与开源许可") { if let url = Catalog.noticesURL { NSWorkspace.shared.open(url) } }
                Link("墨书源代码", destination: URL(string: "https://github.com/gofenix/codeword")!)
                Link("隐私政策", destination: URL(string: "https://gofenix.github.io/codeword/privacy/")!)
                Link("技术支持与数据来源", destination: URL(string: "https://gofenix.github.io/codeword/support/")!)
            }
        }
        .formStyle(.grouped)
        .onAppear { baseURL = model.state.ai.baseURL; aiModel = model.state.ai.model }
        .onDisappear { verifyTask?.cancel() }
        .confirmationDialog("清理学习数据？", isPresented: $clearConfirmation) {
            Button("备份并清理", role: .destructive) { model.clearLearning() }
        } message: { Text("将清理原生版的学习进度、收藏、统计和阅读。会先保留备份；AI 配置另行删除。") }
        .confirmationDialog("删除保存的 AI 配置和钥匙串密钥？", isPresented: $deleteAIConfirmation) {
            Button("删除配置", role: .destructive) {
                do {
                    try Keychain.clear()
                    if model.commit({ $0.ai = AISettings() }) { baseURL = model.state.ai.baseURL; aiModel = model.state.ai.model; newKey = ""; model.keyStored = false; checkMessage = "AI 密钥已删除。" }
                } catch { model.error = error.localizedDescription }
            }
        }
        .sheet(item: $plan) { ImportConfirmation(plan: $0) }
    }

    private func setting<T>(_ path: WritableKeyPath<UserState, T>) -> Binding<T> {
        Binding(get: { model.state[keyPath: path] }, set: { value in model.commit { $0[keyPath: path] = value } })
    }
    private func settings() -> AISettings {
        var s = AISettings(); s.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines); s.model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
    private func saveAI() {
        do {
            let value = settings()
            _ = try ReadingClient.endpoint(value.baseURL, path: "chat/completions")
            guard !value.model.isEmpty else { throw MoshuError.message("请输入服务商提供的模型 ID。") }
            if model.state.ai.baseURL != value.baseURL && !model.state.ai.baseURL.isEmpty && newKey.isEmpty {
                throw MoshuError.message("服务地址已改变。请填入新服务的密钥，或先删除原配置后保存无密钥的本机服务。")
            }
            if !newKey.isEmpty { try Keychain.save(newKey.trimmingCharacters(in: .whitespacesAndNewlines), for: value.baseURL) }
            if model.commit({ $0.ai = value }) { newKey = ""; model.keyStored = Keychain.contains(for: value.baseURL); checkMessage = "已保存。生成阅读前请确认服务地址。" }
        } catch { model.error = error.localizedDescription }
    }
    private func verify() {
        checking = true; checkMessage = ""
        let config = settings()
        verifyTask = Task { @MainActor in
            defer { checking = false }
            do {
                if newKey.isEmpty && config.baseURL != model.state.ai.baseURL && !model.state.ai.baseURL.isEmpty {
                    throw MoshuError.message("测试不同服务前请填写对应密钥，避免把原密钥发送到新地址。")
                }
                let key = newKey.isEmpty ? try Keychain.load(for: config.baseURL) : newKey
                try await ReadingClient().verify(settings: config, key: key)
                try Task.checkCancellation()
                checkMessage = "连接成功。生成能力还取决于所填模型是否支持聊天接口。"
            } catch is CancellationError { checkMessage = "已取消。" }
            catch { checkMessage = "连接失败。\(error.localizedDescription)" }
        }
    }
    private func chooseLegacy() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "选择包含 codeword_review_state.json 等文件的旧版文档文件夹。不读取旧版钥匙串。"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { plan = try model.disk.prepareLegacyImport(from: url) }
        catch { model.error = "导入未完成，当前数据未变。\(error.localizedDescription)" }
    }
    private func chooseNative() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url else { return }
        do { plan = try model.disk.prepareNativeImport(from: url) }
        catch { model.error = "备份无法导入。\(error.localizedDescription)" }
    }
    private func export() {
        let p = NSSavePanel(); p.allowedContentTypes = [.json]; p.nameFieldStringValue = "moshu-backup-\(Codec.dayKey(Date())).json"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let data = model.locked ? try Data(contentsOf: model.disk.stateURL) : try Codec.encoder().encode(model.state)
            try data.write(to: url, options: .atomic)
            model.notice = "备份已导出，不包含 API Key。"
        } catch { model.error = "导出失败。\(error.localizedDescription)" }
    }
}

struct ImportConfirmation: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: ImportPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认合并导入").font(.title2.bold())
            Text("\(plan.incoming.reviews.count) 条进度 · \(plan.incoming.favorites.count) 个收藏 · \(plan.incoming.articles.count) 篇阅读")
            Text("已备份：\(plan.files.joined(separator: "、"))").font(.caption).foregroundStyle(.secondary)
            Text("复习状态按最后复习时间合并；每日统计取较大值。阅读最多保留最新 20 篇。学习模式与当前词书使用导入值。")
            HStack {
                Button("查看备份") { NSWorkspace.shared.open(plan.backupURL) }
                Spacer()
                Button("取消") { dismiss() }
                Button("合并导入") { model.applyImport(plan); dismiss() }.buttonStyle(.glassProminent)
            }
        }.padding(28).frame(width: 560)
    }
}
