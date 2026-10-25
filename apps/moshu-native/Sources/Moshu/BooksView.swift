import SwiftUI
import MoshuCore

struct BooksView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var category = "全部"
    @State private var selected: Book?
    private var filtered: [Book] {
        model.books.filter { (category == "全部" || $0.category == category) && (search.isEmpty || ($0.name + $0.description + $0.category).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("选择一本，开始积累。").font(.largeTitle.bold())
                HStack {
                    Text("正在学习：\(model.book?.name ?? "暂无词书") · \(model.learned.count) 词已学").foregroundStyle(.secondary)
                    Spacer()
                    Button("浏览当前词书与收藏") { selected = model.book }.buttonStyle(.glass)
                }
                HStack {
                    TextField("搜索词书", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Picker("分类", selection: $category) {
                        Text("全部").tag("全部")
                        ForEach(["编程", "考试英语", "青少年英语", "综合"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 200)
                    Spacer()
                    Text("\(filtered.count) 本").foregroundStyle(.secondary)
                }
                if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], spacing: 18) {
                    ForEach(filtered) { book in
                        Button { model.select(book) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(book.emoji).font(.largeTitle)
                                    Spacer()
                                    if model.state.selectedVocabId == book.id { Label("当前学习", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.teal) }
                                }
                                Text(book.name).font(.headline)
                                Text("\(book.category) · \(book.wordCount) 词").font(.callout).foregroundStyle(.secondary)
                                Text(book.description).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                                if model.state.selectedVocabId == book.id {
                                    ProgressView(value: Double(model.learned.count), total: Double(max(1, model.available.count)))
                                }
                            }.frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading).padding(22)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).contextMenu { Button("浏览单词") { selected = book } }
                    }
                }
                Text("词库来源：Qwerty Learner · 当前墨书合并版目录 · 全部离线可用")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
        .sheet(item: $selected) { book in BookBrowser(book: book) }
    }
}

struct BookBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let book: Book
    @State private var words: [Word] = []
    @State private var search = ""
    @State private var filter = "全部"
    @State private var detail: Word?
    @State private var loading = true
    @State private var loadError: String?
    private var filtered: [Word] {
        words.filter { word in
            let categoryMatches: Bool
            switch filter {
            case "收藏": categoryMatches = model.state.favorites.contains(word.id)
            case "已学": categoryMatches = model.state.reviews[word.id]?.lastReviewedAt != nil && !model.state.removed.contains(word.id)
            default: categoryMatches = !model.state.removed.contains(word.id)
            }
            return categoryMatches && (search.isEmpty || word.word.localizedCaseInsensitiveContains(search) || word.translation.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(book.emoji) \(book.name)").font(.title2.bold())
                Spacer()
                Button("选为学习词书") { model.select(book); dismiss() }.buttonStyle(.glassProminent).disabled(loading || loadError != nil)
                Button("关闭") { dismiss() }
            }
            HStack {
                TextField("搜索单词或释义", text: $search).textFieldStyle(.roundedBorder)
                Picker("筛选", selection: $filter) { ForEach(["全部", "收藏", "已学"], id: \.self) { Text($0) } }
                    .frame(width: 150)
            }
            Text("\(filtered.count) 个词 · 点击查看详情、收藏或移出学习").font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let loadError { ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle") }
            else {
                List(filtered) { word in
                    Button { detail = word } label: {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(word.word).font(.headline)
                                Text(word.phonetic).font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 180, alignment: .leading)
                            Text(word.translation).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if model.state.favorites.contains(word.id) { Image(systemName: "star.fill").foregroundStyle(.orange) }
                            Text(model.state.reviews[word.id]?.mastery ?? "待学习").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.listStyle(.inset)
            }
        }.padding(24).frame(width: 800, height: 650)
        .task {
            do {
                let id = book.id
                words = try await Task.detached { try Catalog.words(id) }.value
            } catch { loadError = error.localizedDescription }
            loading = false
        }
        .sheet(item: $detail) { WordDetail(word: $0) }
    }
}
