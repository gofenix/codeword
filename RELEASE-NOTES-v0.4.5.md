# CodeWord v0.4.5 — 本地发音（无 Google TTS）

> 用户反馈："语音发音需要直接集成到 app 内部，谷歌那个有问题！"
>
> 之前 v0.4.0 ~ v0.4.4 用的 `flutter_tts` 是个壳，靠系统 TTS engine（macOS NSSpeechSynthesizer / Android Google TTS）。**Android 上很多人没装 Google TTS / 没下美音语音包 / 国产 ROM 干脆没带**，所以点 🔊 啥反应都没有（v0.4.3 加了 SnackBar 提示，但本质问题没解决）。
>
> v0.4.5 改成 **app 自带音频包**——espeak-ng 在 build 时给每个词合成 OGG Opus，打进 assets，运行时用 audioplayers 播。**不依赖任何系统 TTS / 不需要装任何语音包 / 不联网**。

## 改动 (vs v0.4.4)

| 项 | v0.4.4 | v0.4.5 |
|---|---|---|
| 发音后端 | `flutter_tts` 调系统 TTS | **本地预生成 OGG 音频**（`audioplayers` 播） |
| Android 需要装 Google TTS 引擎 | 是 | **❌ 不需要了** |
| Android 需要下美音语音包 | 是 | **❌ 不需要了** |
| 国产 ROM（无 Google 服务）能用 | 大概率不能 | **✅ 装上就能用** |
| 首次启动下载 | 无 | **无**（所有音频都在 app 里） |
| 音频包大小 | 0 | **1.2 MB**（500 个词 OGG Opus @ 24kbps） |
| macOS 走 | NSSpeechSynthesizer | audioplayers（同样的 OGG） |
| 任何系统 TTS 引擎 | 需要 | **不需要** |

## 怎么做的

**Build 时一次性生成**（`tools/generate_audio.py`）：

```bash
$ python3 tools/generate_audio.py
Generated 500 new audio files (0 skipped, 500 total, 1.2 MB)
```

Pipeline：
1. 读 `apps/codeword/assets/vocab/*.json`（9 个词库 500 词）
2. 对每个词跑 `espeak-ng -v en+m3 -s 175 -p 40 -w tmp.wav "word"`
3. ffmpeg 把 WAV 转成 Opus-in-OGG `@ 24kbps mono`
4. 输出到 `apps/codeword/assets/audio/<wordId>.ogg`

espeak-ng 用的语音是 `en+m3` = 美音 male 变体（不是机器人音，但也不是真人）。

**运行时**：

```dart
// lib/services/tts_service.dart
final player = AudioPlayer();
await player.play(AssetSource('audio/ai_001.ogg'));
```

点 🔊 → audioplayers 播对应 OGG → 完了。零网络、零系统依赖。

## 加了什么

- `tools/generate_audio.py` — build 时音频生成脚本
- `apps/codeword/assets/audio/*.ogg` — 500 个本地音频
- `audioplayers: ^6.1.0` 依赖
- `TtsService` 重写：从 flutter_tts 切到 audioplayers + asset 路径

## 删了什么

- `flutter_tts` 依赖
- `TtsService` 里所有 `setLanguage` / `getEngines` / `isLanguageAvailable` / engine probe 那套逻辑
- "TTS 不可用" SnackBar 里 Google TTS 引擎那条提示

## 体积影响

| | 之前 | 现在 | 增量 |
|---|---|---|---|
| macOS .app | 44 MB | 48 MB | +4 MB |
| macOS DMG | 19 MB | 22 MB | +3 MB |
| Android APK | 46 MB | 47 MB | +1 MB |
| 音频包本身 | 0 | 1.2 MB | +1.2 MB |

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.5-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.5/codeword-0.4.5-macos.dmg) | 22 MB |
| Android | [app-0.4.5-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.5/app-0.4.5-release.apk) | 46 MB |

3 测过：boot / start learning / SM-2 round-trip。

装上 v0.4.5 点 🔊：
- **有声音** → 成了。epeak-ng 美音 male，能听清就行
- **没声音** → SnackBar 会说"本地音频包缺失"，说明 audio 资源没打进 app（理论上不应该发生，但兜底有提示）
- **声音很怪** → 那是 espeak-ng 的味道，习惯就好，不是 bug

## 下一个想动什么

- 5 套剩下词库（LLM / 云原生 / 数据 / 安全 / 业务）灌词 + 灌音频
- 拼写题型？要不要加回来？
- 真上 AI 助手（BYOK，需要先做 key 输入 UI + 加密存储 schema）
- macOS Apple 公证？
