# CodeWord v0.4.3 — TTS 真修 + 错误可见

> v0.4.2 的 TTS 是个哑巴 — 失败也吞错。这次让失败可见，并真正挑 Google TTS 引擎。

## 改动 (vs v0.4.2)

| 项 | v0.4.2 | v0.4.3 |
|---|---|---|
| Android TTS 引擎 | 啥都没挑,默认 | **主动选 Google TTS / Samsung TTS** |
| 失败可见 | `catch(_)` 吞掉,啥都不显示 | `developer.log` + **SnackBar 提示** |
| 默认语言 | en-US（但 probe 失败不报错） | en-US > en-GB > en 顺序 probe，明确报哪个能用 |
| 首次失败 | 静默 | 弹一次长 SnackBar 告诉用户怎么修 |

## 为什么之前静默

旧版 `_AudioButton._speak()` 把 `catch(_)` 写了"吞所有错" — 不管是
- 设备根本没装 TTS 引擎（很多国产 ROM 不带 Google 服务）
- TTS 引擎装了但 en-US 语音数据没下
- plugin 调了底层失败
都被我吞了。结果用户点 🔊 啥反应都没有。

新版 `TtsService`：
1. `getEngines` 列出设备上所有 TTS 引擎
2. 按 `com.google.android.tts` → `com.samsung.tts.engine` → 别的，挑一个
3. `isLanguageAvailable` 探测 en-US → en-GB → en
4. 全部失败 → `_available = false`
5. `speak()` 拿不到 TTS 或调用失败 → 返 `false` + 弹 SnackBar

## 首次失败提示

第一次 TTS 失败时弹一次 6 秒的 SnackBar：

> TTS 不可用 · 请检查 系统设置 → 语言和输入 → 文字转语音 是否装了 Google TTS 引擎 + 美音语音包

之后再失败只弹个短 SnackBar "发音失败: overfitting"。

## 如果你设备真的没 TTS

最干净的解决办法（不靠 Google Play）：

1. **装个第三方 TTS app**（推荐）：
   - [Speech Recognition & Synthesis](https://play.google.com/store/apps/details?id=com.google.android.tts) — Google 官方，4.6★
   - 或者搜"Speech Services by Google"
2. **或者** 系统设置 → 语言和输入 → 文字转语音 → 引擎 → 选一个能用的

如果你看到 SnackBar "TTS 不可用"，**先看下你手机的 `系统设置 → 语言和输入 → 文字转语音` 那一栏是空的还是有 Google TTS**。空的就要装一个。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.3-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.3/codeword-0.4.3-macos.dmg) | 19 MB |
| Android | [app-0.4.3-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.3/app-0.4.3-release.apk) | 44 MB |

3 测过：boot / start learning / SM-2 round-trip。

装上 v0.4.3，先点一下 🔊：
- **有声音** → 成了
- **弹 SnackBar 提示** → 按那个提示去装 TTS
- **没声音也没 SnackBar** → 你之前可能已经选过"不再提示"了，需要把 app 数据清一下重装（也可能是真的没装 TTS 引擎）

挑下一个。
