import SwiftUI
import MoshuCore

@main
struct MoshuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("墨书") {
            RootView().environment(model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 780)
        Settings { SettingsView().environment(model).frame(width: 680, height: 620) }
    }
}

enum Destination: String, CaseIterable, Identifiable {
    case learn = "单词", reading = "阅读", statistics = "图表", books = "词书", settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .learn: "character.book.closed"
        case .reading: "doc.text"
        case .statistics: "chart.bar.xaxis"
        case .books: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(Destination.allCases, selection: $model.destination) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
                    .padding(.vertical, 6)
            }
            .navigationTitle("墨书")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.book?.name ?? "墨书").font(.headline)
                    Text("今天已学习 \(model.todayCount) 词").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        } detail: {
            ZStack {
                LearnView().pageVisible(model.destination == .learn)
                ReadingView(isActive: model.destination == .reading).pageVisible(model.destination == .reading)
                StatisticsView(isActive: model.destination == .statistics).pageVisible(model.destination == .statistics)
                BooksView().pageVisible(model.destination == .books)
                SettingsView().pageVisible(model.destination == .settings)
            }
            .navigationTitle((model.destination ?? .learn).rawValue)
        }
        .tint(.teal)
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .safeAreaInset(edge: .bottom) {
            if let notice = model.notice {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text(notice).font(.callout)
                    Spacer()
                    Button("关闭", systemImage: "xmark") { model.notice = nil }.labelStyle(.iconOnly)
                }.padding(12).background(.regularMaterial)
            }
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct WordDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let word: Word
    @State private var removing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(word.word).font(.largeTitle.bold()).textSelection(.enabled)
                Spacer()
                Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
            }
            Text("\(word.phonetic)  \(word.pos)").foregroundStyle(.secondary)
            Text(word.translations.isEmpty ? word.translation : word.translations.joined(separator: "\n")).font(.title3).textSelection(.enabled)
            if !word.exampleEn.isEmpty { Text(word.exampleEn); Text(word.exampleCn).foregroundStyle(.secondary) }
            if !word.synonyms.isEmpty { Text("近义词：" + word.synonyms.joined(separator: "、")) }
            if !word.antonyms.isEmpty { Text("反义词：" + word.antonyms.joined(separator: "、")) }
            if let r = model.state.reviews[word.id] {
                Text("\(r.mastery) · 间隔 \(r.interval) 天 · 连续回忆 \(r.repetitions) 次").foregroundStyle(.secondary)
                if let due = r.dueAt { Text("下次复习：\(due.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            }
            HStack {
                Button("播放词音", systemImage: "speaker.wave.2") { model.speak(word) }
                Button("系统朗读") { model.speak(word, system: true) }
                Spacer()
                Button(model.state.favorites.contains(word.id) ? "取消收藏" : "收藏", systemImage: "star") { model.favorite(word.id) }
                Button(model.state.removed.contains(word.id) ? "已移出学习" : "移出学习") { removing = true }.disabled(model.state.removed.contains(word.id))
            }.buttonStyle(.glass)
        }.padding(28).frame(width: 600).fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("将此词移出学习队列？", isPresented: $removing) {
            Button("移出学习", role: .destructive) { model.remove(word.id) }
        } message: { Text("该词的记录会保留。清理学习数据会同时清除已移出列表。") }
    }
}

private extension View {
    func pageVisible(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
    }
}
