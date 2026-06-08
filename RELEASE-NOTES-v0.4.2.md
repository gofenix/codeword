# CodeWord v0.4.2 — Android 声音修复 + 选项锚定底部

> 修了两个真用户反馈的问题

## 改动 (vs v0.4.1)

| 项 | v0.4.1 | v0.4.2 |
|---|---|---|
| Android 发音 | MethodChannel 没人接,死链 | **flutter_tts 插件,真出声** |
| macOS 发音 | 同上 | 同上,真的 |
| 选项位置 | 在 `ListView` 里,跟着 prompt 高度变 | **锚定屏幕底部,4 个按钮位置固定** |
| 选项 tap 目标 | 默认 | 56px minHeight + 删了右侧 chevron |

## 详细

### 1. Android 声音

之前 v0.4.0 那个 `MethodChannel('com.codeword/tts')` 的 native 端没写,所以发出去的消息根本没人接。Android 一直静默。

换成了 [`flutter_tts` ^4.2.5](https://pub.dev/packages/flutter_tts),官方维护的跨平台 TTS 插件。`macOS` 用 NSSpeechSynthesizer,`Android` 用系统 TTS engine,首次会弹"安装语音数据"提示,允许后正常发音。

发音按钮在以下位置出现:
- 听音选义题型:词卡右上角 🔊
- 答错单词详情:大词旁边 🔊

### 2. 选项锚定底部

之前选项在 `ListView` 里,占剩余空间。`Column` 上面是 prompt 卡片(高度随内容变),prompt 长的时候选项往上挤,短的时候选项往下沉。**用户的手指记忆是位置不变的**,但选项位置在变,容易点错。

新版:
```
┌──────────────────────┐
│ Progress bar         │
│ ┌──────────────────┐ │
│ │ Question prompt  │ │  ← SingleChildScrollView,内容长可滚
│ │ (scrollable)     │ │
│ └──────────────────┘ │
│ ...空白填充...        │
│ ┌──────────────────┐ │
│ │ A · 选项 1       │ │  ← 固定 Column
│ ├──────────────────┤ │
│ │ B · 选项 2       │ │
│ ├──────────────────┤ │
│ │ C · 选项 3       │ │
│ ├──────────────────┤ │
│ │ D · 选项 4       │ │
│ └──────────────────┘ │
└──────────────────────┘
```

题目内容(prompt + 例句) 超过高度时可滚动,但 4 个选项在屏幕底部位置**永远不变**。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.2-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.2/codeword-0.4.2-macos.dmg) | 19 MB |
| Android | [app-0.4.2-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.2/app-0.4.2-release.apk) | 44 MB |

## 安装

**macOS**:`open <dmg url>` → 拖入 Applications → Gatekeeper 拦照旧 `xattr -d com.apple.quarantine`

**Android**:`adb install <apk url>` 或拷到手机点开,需要开"未知来源"。

## 还在排队

- 6 位同步码 + E2E 加密
- drift 持久化
- 剩下 5 套词库灌词
- macOS Apple 公证(等你给 Developer ID 证书)

挑下一个。
