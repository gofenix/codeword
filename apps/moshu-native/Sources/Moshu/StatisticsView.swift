import SwiftUI
import Charts
import MoshuCore

struct StatisticsView: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @State private var metric = "学习词数"
    @State private var filter = "全部已学"
    @State private var detail: Word?
    @State private var bookProgress: [(String, String, Int, Int)] = []
    @State private var selectedDay: Date?
    private let levels = ["熟悉", "认识", "模糊", "陌生", "待学习"]
    private var days: [Date] {
        (-13...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }
    private var heatmapDays: [Date] { (-89...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) } }
    private var newToday: Int { model.state.reviews.values.filter { $0.firstReviewedAt.map { Calendar.current.isDateInToday($0) } == true && !model.state.removed.contains($0.wordId) }.count }
    private var streak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if model.state.activity[Codec.dayKey(day), default: 0] == 0 { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while model.state.activity[Codec.dayKey(day), default: 0] > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
    private var filtered: [Word] {
        model.available.filter { word in
            let mastery = model.state.reviews[word.id]?.mastery ?? "待学习"
            if filter == "全部已学" { return mastery != "待学习" }
            if filter == "到期复习" { return (model.state.reviews[word.id]?.dueAt ?? .distantFuture) <= Date() }
            return mastery == filter
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("每一点积累，都看得见。").font(.largeTitle.bold())
                HStack(spacing: 16) {
                    Metric(title: "全局已学", value: "\(model.state.reviews.values.filter { $0.lastReviewedAt != nil && !model.state.removed.contains($0.wordId) }.count)", symbol: "book.closed")
                    Metric(title: "连续学习", value: "\(streak) 天", symbol: "flame")
                    Metric(title: "累计时间", value: "\(model.state.studyMinutes.values.reduce(0, +)) 分", symbol: "timer")
                }
                GroupBox("今天") {
                    HStack(spacing: 20) {
                        Label("到期 \(model.due.count) 词", systemImage: "clock")
                        Label("首次学习 \(newToday) 词", systemImage: "sparkles")
                        Label("学习 \(model.state.studyMinutes[Codec.dayKey(Date()), default: 0]) 分钟", systemImage: "timer")
                        Spacer()
                        Button("去学习") { model.destination = .learn }.buttonStyle(.glassProminent)
                    }.padding(14)
                }
                GroupBox("近 14 天 · 全局活动") {
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("统计", selection: $metric) { Text("学习词数").tag("学习词数"); Text("学习分钟").tag("学习分钟") }.pickerStyle(.segmented).frame(width: 260)
                        Chart(days, id: \.self) { day in
                            BarMark(x: .value("日期", day, unit: .day), y: .value(metric, (metric == "学习词数" ? model.state.activity : model.state.studyMinutes)[Codec.dayKey(day), default: 0]))
                                .foregroundStyle(.teal.gradient).cornerRadius(3)
                        }.chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                            .chartXSelection(value: $selectedDay)
                            .frame(height: 190)
                        if let selectedDay {
                            Text("\(selectedDay.formatted(date: .abbreviated, time: .omitted))：\((metric == "学习词数" ? model.state.activity : model.state.studyMinutes)[Codec.dayKey(selectedDay), default: 0]) \(metric == "学习词数" ? "次作答" : "分钟")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(18)
                }
                GroupBox("近 90 天 · 学习足迹") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 18), spacing: 4) {
                        ForEach(heatmapDays, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 3).fill(model.state.activity[Codec.dayKey(day), default: 0] > 0 ? Color.teal : Color.gray.opacity(0.15))
                                .frame(height: 20).help("\(Codec.dayKey(day))：\(model.state.activity[Codec.dayKey(day), default: 0]) 次")
                                .accessibilityLabel("\(Codec.dayKey(day))，\(model.state.activity[Codec.dayKey(day), default: 0]) 次学习")
                        }
                    }.padding(18)
                }
                GroupBox("\(model.book?.name ?? "当前词书") · 掌握分布") {
                    HStack(spacing: 30) {
                        Chart(levels, id: \.self) { level in
                            let count = model.available.filter { (model.state.reviews[$0.id]?.mastery ?? "待学习") == level }.count
                            SectorMark(angle: .value("词数", count), innerRadius: .ratio(0.65), angularInset: 2)
                                .foregroundStyle(by: .value("掌握程度", level))
                        }.chartForegroundStyleScale(domain: levels, range: [Color.teal, .green, .orange, .red, .gray.opacity(0.4)])
                            .frame(width: 300, height: 200)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(levels, id: \.self) { level in
                                HStack { Text(level); Spacer(); Text("\(model.available.filter { (model.state.reviews[$0.id]?.mastery ?? "待学习") == level }.count)").monospacedDigit() }
                            }
                        }.frame(maxWidth: .infinity)
                    }.padding(18)
                }
                GroupBox("各词书学习进度") {
                    LazyVStack(spacing: 14) {
                        ForEach(bookProgress, id: \.0) { row in
                            HStack {
                                Text(row.1).frame(width: 190, alignment: .leading)
                                ProgressView(value: Double(row.2), total: Double(max(1, row.3)))
                                Text("\(row.2) / \(row.3)").font(.caption).monospacedDigit().frame(width: 100, alignment: .trailing)
                            }
                        }
                        if bookProgress.isEmpty { Text("尚无学习记录").foregroundStyle(.secondary) }
                    }.padding(18)
                }
                HStack {
                    Text("当前词书明细").font(.title2.bold())
                    Spacer()
                    Picker("掌握程度", selection: $filter) {
                        ForEach(["全部已学", "到期复习"] + levels, id: \.self) { Text($0) }
                    }.frame(width: 180)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { word in
                        Button { detail = word } label: {
                            HStack {
                                Text(word.word).font(.headline).frame(width: 180, alignment: .leading)
                                Text(word.translation).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(model.state.reviews[word.id]?.mastery ?? "待学习").foregroundStyle(.secondary)
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if filtered.isEmpty { Text("此分类暂无单词").foregroundStyle(.secondary).padding() }
                }
            }.padding(32)
        }
        .sheet(item: $detail) { WordDetail(word: $0) }
        .task(id: "\(isActive)-\(model.state.reviews.count)-\(model.state.removed.count)") {
            guard isActive else { return }
            let reviews = model.state.reviews, removed = model.state.removed, books = model.books
            bookProgress = (try? await Task.detached {
                try books.compactMap { book -> (String, String, Int, Int)? in
                    let words = try Catalog.words(book.id).filter { !removed.contains($0.id) }
                    let count = words.filter { Learning.vocabID(from: $0.id) == book.id && reviews[$0.id]?.lastReviewedAt != nil }.count
                    return count > 0 ? (book.id, book.name, count, words.count) : nil
                }
            }.value) ?? []
        }
    }
}
