// Run: swift scripts/ui-smoke.swift dist/Moshu.app <isolated-fixture-directory>
// Requires macOS Accessibility permission. Uses synthetic progress only.
import AppKit
import ApplicationServices
import Foundation

let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let testRoot = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
if CommandLine.arguments.contains("--article-fixture") {
    let vocabURL = appURL.appendingPathComponent("Contents/Resources/MoshuNative_MoshuCore.bundle/Contents/Resources/Resources/vocab/qwerty_coder.json")
    let vocab = try JSONSerialization.jsonObject(with: Data(contentsOf: vocabURL)) as! [[String: Any]]
    let words = Array(vocab[1...3])
    let now = Date(), future = now.addingTimeInterval(86400), format = ISO8601DateFormatter()
    let ids = words.map { $0["id"] as! String }
    var reviews: [String: Any] = [:]
    for id in ids { reviews[id] = ["wordId": id, "easiness": 250, "interval": 1, "repetitions": 1, "dueAt": format.string(from: future), "lastReviewedAt": format.string(from: now), "firstReviewedAt": format.string(from: now)] }
    let article: [String: Any] = [
        "id": "fixture-article", "createdAt": format.string(from: now), "title": "合成验收短文",
        "articleText": "We abbreviate a long name. An abbreviation shows our ability to communicate clearly. This synthetic article uses learned words for offline reading tests.",
        "translationText": "这是一篇合成的离线阅读验收文章。", "level": "B1", "vocabId": "qwerty_coder", "vocabName": "编程词汇",
        "wordPool": words.map { ["id": $0["id"]!, "word": $0["word"]!, "translation": $0["translation"]!] },
        "questions": (0..<3).map { ["q": "验收问题 \($0 + 1)", "options": ["正确选项", "错误选项一", "错误选项二", "错误选项三"], "correct": 0] as [String: Any] }
    ]
    let state: [String: Any] = ["schemaVersion": 1, "reviews": reviews, "activity": [:], "favorites": [], "removed": [], "openCounts": [:], "studyMinutes": [:], "selectedVocabId": "qwerty_coder", "preferences": ["spellingEnabled": false, "listeningEnabled": false, "learningMode": "quiz"], "ai": ["baseURL": "http://localhost:11434/v1", "model": "test-no-server"], "appearance": "system", "accent": "us", "articles": [article]]
    try JSONSerialization.data(withJSONObject: state).write(to: testRoot.appendingPathComponent("moshu-native.json"))
}
guard AXIsProcessTrusted() else { print("Accessibility access unavailable"); exit(2) }
var environment = ProcessInfo.processInfo.environment
environment["MOSHU_DATA_DIRECTORY"] = testRoot.path
environment["MOSHU_DISABLE_AUDIO_NETWORK"] = "1"
let configuration = NSWorkspace.OpenConfiguration()
configuration.environment = environment
configuration.createsNewApplicationInstance = true
configuration.activates = true
var running: NSRunningApplication?
var launchError: Error?
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in running = app; launchError = error }
let launchDeadline = Date().addingTimeInterval(10)
while running == nil && launchError == nil && Date() < launchDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
guard let running else { throw launchError ?? NSError(domain: "App launch timed out", code: 0) }
func stopApp() {
    if !running.isTerminated { running.terminate() }
    let deadline = Date().addingTimeInterval(3)
    while !running.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    if !running.isTerminated { running.forceTerminate() }
}
defer { stopApp() }
let application = AXUIElementCreateApplication(running.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func nodes(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if depth > 24 { return [] }
    // Inspect only this application's windows, never the system Apple menu.
    let children = attribute(element, depth == 0 ? kAXWindowsAttribute : kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [element] + children.prefix(180).flatMap { nodes($0, depth: depth + 1) }
}
func text(_ e: AXUIElement) -> String {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(e, $0) as? String }.joined(separator: " ")
}
func role(_ e: AXUIElement) -> String { attribute(e, kAXRoleAttribute) as? String ?? "" }
func waitFor(_ label: String, seconds: TimeInterval = 8) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if let found = nodes(application).first(where: { text($0).contains(label) }) { return found }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline && !running.isTerminated
    return nil
}
func press(_ label: String) throws {
    guard let element = waitFor(label) else { throw NSError(domain: "Missing UI: \(label)", code: 1) }
    if role(element) == "AXStaticText", let rawPosition = attribute(element, kAXPositionAttribute), let rawSize = attribute(element, kAXSizeAttribute) {
        var point = CGPoint.zero, size = CGSize.zero
        let position = unsafeBitCast(rawPosition, to: AXValue.self), dimensions = unsafeBitCast(rawSize, to: AXValue.self)
        if AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(dimensions, .cgSize, &size) {
            let center = CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
            return
        }
    }
    var target = element
    for _ in 0..<4 {
        if AXUIElementPerformAction(target, kAXPressAction as CFString) == .success { return }
        guard let parent = attribute(target, kAXParentAttribute) else { break }
        target = unsafeBitCast(parent, to: AXUIElement.self)
    }
    throw NSError(domain: "Unable to press: \(label)", code: 2)
}
func capture(_ name: String) throws {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == running.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
          let number = window[kCGWindowNumber as String] as? Int else { return }
    let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-l", String(number), testRoot.appendingPathComponent(name + ".png").path]
    try shot.run(); shot.waitUntilExit()
    guard shot.terminationStatus == 0 else { throw NSError(domain: "Screenshot unavailable", code: 3) }
}

do {
    running.activate()
    guard waitFor("看单词选释义") != nil else { throw NSError(domain: "Learning screen did not load", code: 4) }
    try capture("01-learning")
    if CommandLine.arguments.contains("--inspect") {
        for e in nodes(application).prefix(100) where !text(e).isEmpty { print("\(role(e)): \(text(e).prefix(150))") }
    } else {
        try press("不知道，查看解析")
        guard waitFor("再记一次") != nil else { throw NSError(domain: "Wrong answer detail missing", code: 5) }
        try capture("02-wrong-answer")
        try press("继续，稍后重试")
        try press("阅读")
        guard waitFor("阅读书架") != nil else { throw NSError(domain: "Reading screen missing", code: 6) }
        try capture("03-reading")
        if CommandLine.arguments.contains("--article-fixture") {
            try press("合成验收短文")
            guard waitFor("朗读全文") != nil else { throw NSError(domain: "Saved article not open", code: 11) }
            try press("中文翻译")
            guard waitFor("这是一篇合成的离线阅读验收文章") != nil else { throw NSError(domain: "Translation missing", code: 12) }
            try press("正确选项")
            guard waitFor("回答正确") != nil else { throw NSError(domain: "Comprehension result missing", code: 13) }
            try capture("07-saved-article")
            try press("查看单词释义：abbreviate")
            guard waitFor("下次复习") != nil else { throw NSError(domain: "Word detail missing", code: 14) }
            try capture("08-word-detail")
            try press("关闭")
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            try press("完成")
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        try press("图表")
        guard waitFor("近 14 天") != nil else { throw NSError(domain: "Statistics screen missing", code: 7) }
        try capture("04-statistics")
        try press("词书")
        guard waitFor("选择一本") != nil else { throw NSError(domain: "Book screen missing", code: 8) }
        try capture("05-books")
        try press("设置")
        guard waitFor("听音选释义") != nil else { throw NSError(domain: "Settings screen missing", code: 9) }
        try capture("06-settings")
        try press("单词")
        guard waitFor("已答 1") != nil else { throw NSError(domain: "Session state not retained", code: 10) }
        print("PASS: launch, answer persistence, wrong detail, retry, five pages, retained session")
    }
} catch {
    print("FAIL: \(error.localizedDescription)")
    for e in nodes(application).prefix(100) where !text(e).isEmpty { print("\(role(e)): \(text(e).prefix(150))") }
    stopApp()
    exit(1)
}
