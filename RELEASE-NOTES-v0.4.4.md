# CodeWord v0.4.4 — Local-first 审计

> 把所有和 local-first 不符的代码全删了。

## 原则（确认版）

> 不做云端，不做登录。所有单词数据、进度数据都是单机的。和 AI 相关的功能都是 BYOK 的形式保存在本地加密存储。

## 改动 (vs v0.4.3)

| 项 | v0.4.3 | v0.4.4 |
|---|---|---|
| `lib_sync` 包 | 空脚手架（pubspec 在） | **删了** |
| 我的 tab 同步码 | "W4 上线 · 6 位码 + E2E 加密" 占位 | **删了** |
| 我的 tab AI Key | 没占位 | 加了"BYOK · 本地加密存储" 占位 |
| 我的 tab 关于 | "v0.2.0-w2" | "v0.4.4" |
| 我的 tab 发音 | "英音 · 系统默认" | "美音 (en-US) · 系统默认" |
| `pointycastle` 依赖 | 在 | **删了** |
| `drift` / `sqlite3_flutter_libs` 依赖 | 在（未用） | **删了** |
| `flutter_secure_storage` | 没装 | **装了**（准备 BYOK 用） |
| README | 写 lib_sync | 重写原则段 |

## 审计结果（全代码 grep）

| 检查项 | 结果 |
|---|---|
| `http` / `dart:io` 网络调用 | ❌ 无 |
| Firebase / Supabase / Amplitude / Sentry | ❌ 无 |
| 任何 cloud SDK | ❌ 无 |
| Login / OAuth / JWT | ❌ 无 |
| 同步码 / cloud sync / 6位码 | ❌ 删干净 |
| 单词数据来源 | `rootBundle.loadString('assets/vocab/...')` 本地 asset |
| 复习进度存储 | `getApplicationDocumentsDirectory()/codeword_review_state.json` 本地文件 |
| TTS | 平台系统 TTS（Keychain / Android 系统 TTS engine） |
| 计划中的 BYOK 存储 | `flutter_secure_storage` (Keychain on macOS, EncryptedSharedPreferences on Android) |

**结论：整个 app 一个外部网络请求都没有。**

## v0.4.4 不再排队了

之前 v0.4.2/3 release notes 里写的"还在排队"：

- 🚧 ~~6 位同步码 + E2E 加密~~ — **永久删除**（违反 local-first）
- 🚧 ~~drift 持久化~~ — 已经在用 JSON 文件本地存，够用
- 🚧 ~~剩下 5 套词库灌词~~ — 还在排队

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.4-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.4/codeword-0.4.4-macos.dmg) | 19 MB |
| Android | [app-0.4.4-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.4/app-0.4.4-release.apk) | 44 MB |

3 测过。挑下一个。
