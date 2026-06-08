# CodeWord v0.4.1 — 答对零延迟

> 修了 v0.4.0 那个"答对弹个绿框才下一题"的过渡页

## 改动 (vs v0.4.0)

| 项 | v0.4.0 | v0.4.1 |
|---|---|---|
| 答对 | 弹 ✓ 绿框 → 800ms 后下一题 | **直接下一题**，没有中间页 |
| 答错 | 单词详情卡 → 点按钮下一题 | 同 v0.4.0（保留） |
| 拼写题型 | 有 | **砍了**（之前问题太多） |
| 题型 | 5 种 | 4 种：看词选义 / 看义选词 / 听音选义 / 语境选词 |
| macOS | ad-hoc 签名 | 同 |
| Android | release APK | 同 |

答对时整个屏幕不会有任何中间状态：选完 A/B/C/D，下一题的词卡直接就位。
答错时仍然会展示单词详情（单词/音标/中文释义/中英例句/同义/反义），看明白了点"记住了,下一题"。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.1-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.1/codeword-0.4.1-macos.dmg) | 19 MB |
| Android | [app-0.4.1-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.1/app-0.4.1-release.apk) | 44 MB |

## macOS 安装

```bash
open https://github.com/gofenix/codeword/releases/download/v0.4.1/codeword-0.4.1-macos.dmg
```

挂载 → 拖入 Applications → 首次被 Gatekeeper 拦：
- `系统设置 → 隐私与安全性` → 仍要打开
- 或 `xattr -d com.apple.quarantine /Applications/CodeWord.app`

## Android 安装

```bash
# 用 adb 或直接拷到手机点开
adb install https://github.com/gofenix/codeword/releases/download/v0.4.1/app-0.4.1-release.apk
```

未签名（debug-key），需要你手机开"未知来源"。

## 还在排队

- 6 位同步码 + E2E 加密
- 音标发音（platform TTS 通道已铺好）
- drift 持久化（已经是 JSON 文件,W3 转 SQLite）
- 剩下 5 套词库灌词（LLM / 云原生 / 数据 / 安全 / 业务）

挑下一个想做的。
