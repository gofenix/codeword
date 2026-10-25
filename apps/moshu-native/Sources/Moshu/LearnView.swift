import SwiftUI
import MoshuCore

@MainActor @Observable
final class LearningSession {
    let model: AppModel
    var questions: [Question] = []
    var index = 0
    var correct = 0
    var answered = 0
    var wrong = false
    var revealed = false
    var typed = ""
    var scored: Set<String> = []
    var startedAt = Date()
    var lastInteraction: Date?
    var activeSeconds = 0
    var history: [Question] = []
    var kindSerial = 0
    var queued: Set<String> = []
    var previousMode: String

    init(model: AppModel) { self.model = model; previousMode = model.state.preferences.learningMode; refill() }
    var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    var finished: Bool { current == nil }

    func refill() {
        questions = []; index = 0
        fillBuffer()
        resetPrompt()
    }

    func fillBuffer() {
        guard questions.count - index <= 5 else { return }
        let remaining = model.words.filter { !scored.contains($0.id) && !queued.contains($0.id) }
        let words = Learning.eligible(words: remaining, state: model.state, limit: max(0, 16 - (questions.count - index)))
        let appended = words.map { word in
            let kinds = Learning.kinds(model.state.preferences)
            let kind = kinds[kindSerial % kinds.count]; kindSerial += 1
            return Learning.question(word, kind: kind, pool: model.available)
        }
        questions.append(contentsOf: appended)
        queued.formUnion(words.map(\.id))
    }

    func preferencesChanged() {
        let mode = model.state.preferences.learningMode
        let returningFromCards = previousMode == "swipe"
        previousMode = mode
        guard mode != "swipe" else { return }
        let kinds = Learning.kinds(model.state.preferences)
        for i in index..<questions.count {
            if i == index && (!returningFromCards || wrong) { continue }
            let old = questions[i]
            questions[i] = Learning.question(old.word, kind: kinds[kindSerial % kinds.count], pool: model.available, retry: old.retry)
            kindSerial += 1
        }
        if returningFromCards { typed = ""; revealed = false; startedAt = Date() }
    }

    func answer(_ quality: Int, objective: Bool = true) {
        guard let q = current, !wrong else { return }
        let now = Date()
        let elapsed = lastInteraction.map { max(1, min(60, Int(now.timeIntervalSince($0)))) } ?? 0
        let newSeconds = activeSeconds + elapsed
        let fresh = !q.retry && !scored.contains(q.word.id)
        if fresh {
            let saved = model.commit {
                $0.reviews[q.word.id] = ($0.reviews[q.word.id] ?? Review(wordId: q.word.id)).scheduled(quality: quality, now: now)
                $0.activity[Codec.dayKey(now), default: 0] += 1
                $0.studyMinutes[Codec.dayKey(now), default: 0] += newSeconds / 60
            }
            guard saved else { return }
            scored.insert(q.word.id); activeSeconds = newSeconds % 60
        }
        lastInteraction = now
        answered += 1
        if quality >= 3 { correct += 1 }
        if quality < 3 && objective { wrong = true; revealed = true }
        else { advance() }
    }

    func continueAfterWrong(skip: Bool = false) {
        guard let q = current, wrong else { return }
        if !skip && !q.retry {
            let kinds = Learning.kinds(model.state.preferences).filter { $0 != q.kind }
            let retry = Learning.question(q.word, kind: kinds.first ?? .spelling, pool: model.available, retry: true)
            questions.insert(retry, at: min(questions.count, index + Int.random(in: 4...6)))
        }
        advance()
    }

    func back() {
        guard !wrong, let previous = history.popLast() else { return }
        let revisited = Learning.question(previous.word, kind: previous.kind, pool: model.available, retry: true)
        questions.insert(revisited, at: index)
        resetPrompt()
    }

    func advance() {
        if let q = current { history.append(q); if history.count > 64 { history.removeFirst() } }
        index += 1
        if index > 64 { questions.removeFirst(index); index = 0 }
        fillBuffer()
        resetPrompt()
    }
    private func resetPrompt() {
        wrong = false; revealed = false; typed = ""; startedAt = Date(); model.audio.stop()
        if let word = current?.word { model.speak(word) }
    }

    func removedChanged() {
        let old = current?.id
        if index < questions.count {
            questions.replaceSubrange(index..., with: questions[index...].filter { !model.state.removed.contains($0.word.id) })
        }
        fillBuffer()
        if old != current?.id { resetPrompt() }
    }
}

struct LearnView: View {
    @Environment(AppModel.self) private var model
    @State private var session: LearningSession?
    var body: some View {
        Group {
            if let session { SessionView(session: session, onEnd: { self.session = nil }) }
            else { landing }
        }
        .onAppear { if session == nil && !model.locked { session = LearningSession(model: model) } }
        .onChange(of: model.state.selectedVocabId) { session = LearningSession(model: model) }
        .onChange(of: model.dataGeneration) { session = LearningSession(model: model) }
    }

    private var landing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide))).foregroundStyle(.secondary)
                    Text("把今天的词，记得更久。").font(.largeTitle.bold())
                    Text("先复习到期词，再学习新词。每次 20 词，按自己的节奏继续。").foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Metric(title: "待复习", value: "\(model.due.count)", symbol: "clock")
                    Metric(title: "本书已学", value: "\(model.learned.count)", symbol: "checkmark.seal")
                    Metric(title: "今日学习", value: "\(model.todayCount)", symbol: "sun.max")
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(model.book?.emoji ?? "📘").font(.system(size: 44))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.book?.name ?? "词书").font(.title2.bold())
                                Text("\(model.available.count) 词 · \(model.learned.count) 词已学").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("开始学习", systemImage: "play.fill") { session = LearningSession(model: model) }
                                .buttonStyle(.glassProminent).controlSize(.large).disabled(model.locked || model.available.isEmpty)
                        }
                        ProgressView(value: Double(model.learned.count), total: Double(max(1, model.available.count)))
                        Picker("学习模式", selection: Binding(get: { model.state.preferences.learningMode }, set: { value in model.commit { $0.preferences.learningMode = value } })) {
                            Text("选择与拼写").tag("quiz")
                            Text("翻卡片").tag("swipe")
                        }.pickerStyle(.segmented)
                    }.padding(18)
                }
                Label("听音和拼写可在设置中开启。错题会展示解析，稍后换一种题型重现。", systemImage: "lightbulb")
                    .font(.callout).foregroundStyle(.secondary)
                if model.learned.isEmpty {
                    ContentUnavailableView("从第一个词开始", systemImage: "leaf", description: Text("在词书页切换词书，或在设置中导入旧版进度。"))
                }
            }.padding(32).frame(maxWidth: 1000)
        }
    }
}

struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: LearningSession
    let onEnd: () -> Void
    @State private var detail: Word?
    @State private var cardHeight: CGFloat = 500
    @State private var removing = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("结束学习", systemImage: "chevron.left") { model.audio.stop(); onEnd() }
                Spacer()
                Text("已答 \(session.answered) · 正确 \(session.correct)").monospacedDigit().foregroundStyle(.secondary)
                Picker("模式", selection: Binding(get: { model.state.preferences.learningMode }, set: { value in model.commit { $0.preferences.learningMode = value } })) {
                    Text("答题").tag("quiz"); Text("卡片").tag("swipe")
                }.pickerStyle(.segmented).frame(width: 140).disabled(session.wrong)
            }
            ProgressView(value: Double(session.index), total: Double(max(1, session.questions.count)))
            if let message = model.audioMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let q = session.current {
                ScrollView {
                    VStack(spacing: 22) {
                        HStack {
                            Text(q.retry ? "巩固重现 · 不重复计入进度" : model.state.reviews[q.word.id] == nil ? "新词" : "到期复习")
                            Spacer()
                            Button(model.state.favorites.contains(q.word.id) ? "已收藏" : "收藏", systemImage: model.state.favorites.contains(q.word.id) ? "star.fill" : "star") { model.favorite(q.word.id) }
                            Button("移出", systemImage: "minus.circle") { removing = true }
                        }.font(.caption).foregroundStyle(.secondary)
                        if model.state.preferences.learningMode == "swipe" { card(q) }
                        else { quiz(q) }
                        if session.wrong { wrongDetail(q) }
                    }.padding(28).frame(maxWidth: 760)
                }.frame(maxWidth: .infinity)
            } else {
                Spacer()
                ContentUnavailableView("当前没有待学单词", systemImage: "checkmark.seal", description: Text("本次作答 \(session.answered) 次，正确 \(session.correct) 次。可以去阅读复现，或选择另一本词书。"))
                Button("返回") { onEnd() }
                Spacer()
            }
        }.padding(24)
        .sheet(item: $detail) { WordDetail(word: $0) }
        .onChange(of: model.state.preferences) { session.preferencesChanged() }
        .onChange(of: model.state.removed) { session.removedChanged() }
        .onDisappear { model.audio.stop() }
        .confirmationDialog("将此词移出学习队列？", isPresented: $removing) {
            Button("移出学习", role: .destructive) { if let word = session.current?.word { model.remove(word.id) } }
        } message: { Text("该词的记录会保留。清理学习数据会同时清除已移出列表。") }
    }

    private func card(_ q: Question) -> some View {
        VStack(spacing: 22) {
            VStack {
                VStack(spacing: 20) {
                    Text(q.word.word).font(.system(size: 46, weight: .semibold, design: .rounded))
                    Text("\(q.word.phonetic) \(q.word.pos)").foregroundStyle(.secondary)
                    Text(q.word.translation).font(.title2)
                    if !q.word.exampleEn.isEmpty { Text(q.word.exampleEn).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, minHeight: 260).padding(24)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 24))
            }
            audioButtons(q.word)
            GlassEffectContainer {
                HStack(spacing: 16) {
                    Button("上一个", systemImage: "arrow.left") { session.back() }.disabled(session.history.isEmpty)
                    Button("不认识") { session.answer(0, objective: false) }
                    Button("再看看") { session.answer(3, objective: false) }
                    Button("下一个", systemImage: "arrow.right") {
                        let milliseconds = Int(Date().timeIntervalSince(session.startedAt) * 1000)
                        session.answer(Learning.swipeQuality(milliseconds: milliseconds, review: model.state.reviews[q.word.id]), objective: false)
                    }.buttonStyle(.glassProminent)
                }.buttonStyle(.glass).controlSize(.large)
            }
            Text("下一个按停留时间评分：8 秒内记住了，18 秒内再看看；熟词 3 秒内为熟悉。也可直接点“不认识”或“再看看”。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.height < -cardHeight * 0.3 || value.velocity.height < -500 {
                session.answer(Learning.swipeQuality(milliseconds: Int(Date().timeIntervalSince(session.startedAt) * 1000), review: model.state.reviews[q.word.id]), objective: false)
            } else if value.translation.height > cardHeight * 0.3 || value.velocity.height > 500 { session.back() }
        })
        .accessibilityAction(named: Text("下一个")) { session.answer(Learning.swipeQuality(milliseconds: 5000, review: model.state.reviews[q.word.id]), objective: false) }
        .accessibilityAction(named: Text("上一个")) { session.back() }
    }

    private func quiz(_ q: Question) -> some View {
        VStack(spacing: 18) {
            Text(q.kind.label).font(.callout).foregroundStyle(.secondary)
            if q.kind == .listening {
                Button("播放单词", systemImage: "speaker.wave.2.fill") { model.speak(q.word) }.buttonStyle(.glassProminent).controlSize(.extraLarge)
                Button("离线系统朗读") { model.speak(q.word, system: true) }.font(.caption)
            } else {
                Text(q.kind == .meaning ? q.word.word : Learning.compactMeaning(q.word.translation))
                    .font(q.kind == .meaning ? .system(size: 42, weight: .semibold) : .title2)
                    .multilineTextAlignment(.center).frame(minHeight: 68)
                if q.kind == .meaning { Text(q.word.phonetic).foregroundStyle(.secondary) }
            }
            if q.kind == .spelling {
                TextField("输入英文单词", text: $session.typed).textFieldStyle(.roundedBorder).font(.title2)
                    .onSubmit { submitTyped(q) }.disabled(session.wrong)
                Button("提交") { submitTyped(q) }.buttonStyle(.glassProminent).disabled(session.wrong || session.typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                    Button { session.answer(i == q.correctIndex ? 4 : 0) } label: {
                        HStack { Text("\(i + 1)").foregroundStyle(.secondary).frame(width: 24); Text(option).foregroundStyle(.primary); Spacer() }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered).disabled(session.wrong)
                }
            }
            if !session.wrong { Button("不知道，查看解析") { session.answer(0) }.foregroundStyle(.secondary) }
        }
    }

    private func submitTyped(_ q: Question) {
        guard !session.typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.answer(Learning.typedCorrect(session.typed, word: q.word) ? 4 : 0)
    }

    private func wrongDetail(_ q: Question) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("再记一次", systemImage: "arrow.trianglehead.clockwise").foregroundStyle(.orange)
                Text(q.word.word).font(.title.bold())
                Text(q.word.translation).font(.title3)
                if !q.word.exampleEn.isEmpty { Text(q.word.exampleEn); Text(q.word.exampleCn) }
                audioButtons(q.word)
                HStack {
                    Button("继续，稍后重试") { session.continueAfterWrong() }.buttonStyle(.glassProminent)
                    Button("跳过重试") { session.continueAfterWrong(skip: true) }
                    Spacer()
                    Button("详细释义") { detail = q.word }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
    private func audioButtons(_ word: Word) -> some View {
        HStack {
            Button("词音", systemImage: "speaker.wave.2") { model.speak(word) }
            Button("系统朗读") { model.speak(word, system: true) }
        }.buttonStyle(.glass)
    }
}
