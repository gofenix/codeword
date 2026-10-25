import SwiftUI
import MoshuCore

struct ReadingView: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var current: Article?
    @State private var settings = false
    @State private var generating = false
    @State private var task: Task<Void, Never>?
    @State private var message: String?
    @State private var search = ""
    @State private var rotation = 0

    private var candidates: [Word] {
        Array(model.learned.sorted { a, b in
            let ar = model.state.reviews[a.id]!, br = model.state.reviews[b.id]!
            let ad = (ar.dueAt ?? .distantFuture) <= Date(), bd = (br.dueAt ?? .distantFuture) <= Date()
            if ad != bd { return ad }
            return (ar.lastReviewedAt ?? .distantPast) > (br.lastReviewedAt ?? .distantPast)
        }.prefix(24))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("让单词，走进故事。").font(.largeTitle.bold())
                        Text("从已学词中选 3–10 个，生成一篇短文和三道理解题。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("AI 配置", systemImage: "slider.horizontal.3") { settings = true }.buttonStyle(.glass)
                }
                GroupBox("\(model.book?.name ?? "当前词书") · 选词") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("已选 \(selected.count) 词").monospacedDigit()
                            Spacer()
                            Button("换一批") { rotate() }.disabled(generating)
                        }
                        if candidates.count < 3 {
                            ContentUnavailableView("先积累 3 个已学词", systemImage: "character.book.closed", description: Text("完成学习后，就能在这里复现它们。也可以从设置导入旧版进度。"))
                        } else {
                            TextField("筛选已学单词", text: $search).textFieldStyle(.roundedBorder)
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 10) {
                                    ForEach(candidates.filter { search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) }) { word in
                                        Toggle(isOn: Binding(get: { selected.contains(word.id) }, set: { value in
                                            if value && selected.count < 10 { selected.insert(word.id) }
                                            else if !value { selected.remove(word.id) }
                                        })) { Text(word.word).lineLimit(1).help(word.translation) }
                                        .toggleStyle(.checkbox).disabled(generating || (!selected.contains(word.id) && selected.count >= 10))
                                    }
                                }.padding(4)
                            }.frame(maxHeight: 180)
                            HStack {
                                Button(generating ? "正在生成…" : "生成阅读", systemImage: "sparkles") { generate() }
                                    .buttonStyle(.glassProminent).controlSize(.large)
                                    .disabled(generating || selected.count < 3 || !model.aiConfigured)
                                if generating { ProgressView().controlSize(.small); Button("取消") { task?.cancel(); generating = false } }
                            }
                            if !model.aiConfigured { Text("请先配置你自己的 AI 服务，费用由服务商收取。").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    }.padding(18)
                }
                HStack { Text("阅读书架").font(.title2.bold()); Spacer(); Text("\(model.state.articles.count) / 20 篇").foregroundStyle(.secondary) }
                if model.state.articles.isEmpty {
                    ContentUnavailableView("故事还没开始", systemImage: "doc.text", description: Text("生成的阅读会自动保存到本机，最近 20 篇可离线阅读。"))
                }
                ForEach(model.state.articles) { article in
                    HStack {
                        Button { current = article } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(article.title.isEmpty ? "单词短文" : article.title).font(.title3.bold())
                                Text(article.articleText).lineLimit(2).foregroundStyle(.secondary)
                                Text("\(article.vocabName) · \(article.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(article.wordPool.count) 个词").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.padding(22).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(32)
        }
        .onAppear { if selected.isEmpty { selected = Set(candidates.prefix(10).map(\.id)) } }
        .onChange(of: isActive) { _, active in
            if !active { task?.cancel(); generating = false }
            else if selected.isEmpty { selected = Set(candidates.prefix(10).map(\.id)) }
        }
        .onChange(of: model.state.selectedVocabId) { task?.cancel(); generating = false; selected = Set(candidates.prefix(10).map(\.id)) }
        .onChange(of: model.dataGeneration) { task?.cancel(); generating = false; selected = Set(candidates.prefix(10).map(\.id)) }
        .onChange(of: model.state.ai) { task?.cancel(); generating = false }
        .onDisappear { task?.cancel() }
        .sheet(item: $current) { ArticleReader(article: $0) }
        .sheet(isPresented: $settings) { SettingsView().frame(width: 700, height: 680) }
    }

    private func rotate() {
        let due = candidates.filter { (model.state.reviews[$0.id]?.dueAt ?? .distantFuture) <= Date() }
        let rest = candidates.filter { !Set(due.map(\.id)).contains($0.id) }
        let count = min(10, candidates.count)
        rotation += max(1, count - due.count)
        let rotated = rest.isEmpty ? [] : Array(rest.dropFirst(rotation % rest.count) + rest.prefix(rotation % rest.count))
        let next = Set((due + rotated).prefix(count).map(\.id))
        if next == selected { message = "已经是当前最适合复现的词" }
        else { selected = next; message = nil }
    }

    private func generate() {
        guard !generating, let book = model.book else { return }
        let words = candidates.filter { selected.contains($0.id) }, generation = model.dataGeneration, config = model.state.ai
        generating = true; message = nil
        task = Task { @MainActor in
            defer { generating = false }
            do {
                let key = try Keychain.load(for: config.baseURL)
                let reading = try await ReadingClient().generate(settings: config, key: key, words: words, theme: book.name)
                try Task.checkCancellation()
                guard isActive, generation == model.dataGeneration, book.id == model.state.selectedVocabId, config == model.state.ai else { return }
                let article = Article(title: reading.title, text: reading.article, translation: reading.translation, book: book, words: words, questions: reading.questions)
                if model.commit({ $0.articles.insert(article, at: 0); $0.articles = Array($0.articles.prefix(20)) }) { current = article }
            } catch is CancellationError { message = "生成已取消。" }
            catch { message = "生成失败。\(error.localizedDescription)" }
        }
    }
}

struct ArticleReader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let article: Article
    @State private var translation = false
    @State private var answers: [Int: Int] = [:]
    @State private var detail: Word?

    private var highlighted: AttributedString {
        var result = AttributedString(article.articleText)
        for entry in article.wordPool {
            guard let text = entry["word"], !text.isEmpty else { continue }
            let pattern = "(?i)(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: text) + "(?![A-Za-z])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let source = article.articleText
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source),
                      let start = AttributedString.Index(range.lowerBound, within: result), let end = AttributedString.Index(range.upperBound, within: result) else { continue }
                let key = entry["id"] ?? text
                var c = URLComponents(); c.scheme = "moshu"; c.host = "word"; c.queryItems = [URLQueryItem(name: "id", value: key)]
                result[start..<end].link = c.url
                result[start..<end].foregroundColor = .teal
                result[start..<end].font = .system(size: 19, weight: .semibold)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("中文翻译") { translation.toggle() }.buttonStyle(.glass)
                Button("朗读全文", systemImage: "speaker.wave.2") {
                    Task { try? await model.audio.speak(article.articleText, accent: model.state.accent, system: true) }
                }.buttonStyle(.glass)
                Button("停止") { model.audio.stop() }
                Spacer()
                Button("完成") { model.audio.stop(); dismiss() }.buttonStyle(.glassProminent)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(article.title.isEmpty ? "单词短文" : article.title).font(.largeTitle.bold())
                    Text("\(article.vocabName) · \(article.createdAt.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(.secondary)
                    Text(highlighted).font(.system(size: 19)).lineSpacing(10).textSelection(.enabled)
                        .environment(\.openURL, OpenURLAction { url in
                            guard url.scheme == "moshu", let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                                  let id = c.queryItems?.first(where: { $0.name == "id" })?.value else { return .discarded }
                            if let word = model.words.first(where: { $0.id == id }) { detail = word }
                            else if let entry = article.wordPool.first(where: { ($0["id"] ?? $0["word"]) == id }) {
                                detail = Word(id: id, word: entry["word"] ?? id, translation: entry["translation"] ?? "", domain: article.vocabId)
                            }
                            return .handled
                        })
                    if translation { GroupBox("中文翻译") { Text(article.translationText.isEmpty ? "这篇历史文章没有保存译文" : article.translationText).lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).padding() } }
                    Text("目标词").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading) {
                        ForEach(Array(article.wordPool.enumerated()), id: \.offset) { _, entry in
                            Button {
                                let id = entry["id"] ?? entry["word"] ?? ""
                                detail = model.words.first { $0.id == id } ?? Word(id: id, word: entry["word"] ?? "", translation: entry["translation"] ?? "", domain: article.vocabId)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(entry["word"] ?? "").bold()
                                    Text(entry["translation"] ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            }.buttonStyle(.plain).accessibilityLabel("查看单词释义：\(entry["word"] ?? "")")
                        }
                    }
                    Divider()
                    Text("理解练习").font(.title2.bold())
                    ForEach(Array((article.questions ?? []).enumerated()), id: \.offset) { i, question in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(i + 1). \(question.q)").font(.headline)
                            ForEach(Array(question.options.enumerated()), id: \.offset) { j, option in
                                Button { answers[i] = j } label: {
                                    HStack {
                                        Text(option).foregroundStyle(.primary)
                                        Spacer()
                                        if answers[i] != nil, j == question.correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                        else if answers[i] == j { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.bordered).disabled(answers[i] != nil)
                            }
                            if let answer = answers[i] { Text(answer == question.correct ? "回答正确" : "正确答案：\(question.options[question.correct])").foregroundStyle(answer == question.correct ? .green : .orange) }
                        }.padding(.vertical, 8)
                    }
                    if !answers.isEmpty { Button("重新练习") { answers = [:] } }
                    Text("内容由你选择的 AI 服务生成。").font(.caption).foregroundStyle(.secondary)
                }.padding(32)
            }
        }.frame(width: 820, height: 740)
        .sheet(item: $detail) { WordDetail(word: $0) }
        .onDisappear { model.audio.stop() }
    }
}
