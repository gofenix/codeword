# 墨书 · SwiftUI 原生版

macOS 26+ 的原生墨书。SwiftUI 页面、Swift 业务、Swift Charts 图表、AVFoundation 发音与系统钥匙串；没有 Flutter 引擎、WebView 或 Dart 运行时依赖。本次交付为 Apple Silicon macOS 应用，iOS、Android 和 Web 不在迁移范围内。

## 启动和构建

解压交付的 `Moshu-macOS-arm64.zip`，将 `Moshu.app` 拖到“应用程序”，双击打开。预览包使用本地 ad hoc 签名，尚未公证；如系统阻止从下载位置打开，可在系统“隐私与安全性”中确认打开，或从源码构建。它与现有 Flutter 墨书使用不同的应用标识和数据目录，可以并存。

从仓库根目录运行（Xcode 26+、Swift 6.2+）：

```sh
apps/moshu-native/scripts/test.sh
apps/moshu-native/scripts/build.sh
open apps/moshu-native/dist/Moshu.app
```

构建脚本从现有 `apps/codeword/assets/vocab` 复制词库到 SwiftPM 的资源目录，再构建 Release、生成图标、打包应用、签名并校验。资源副本和构建产物不提交 Git。没有第三方 Swift 包依赖；首次构建不需要下载依赖。

## 已实现功能

| 入口 | 行为 |
| --- | --- |
| 单词 | 自动进入当前词书；默认两种选择题，可开启听音和拼写；卡片竖滑、回退和停留评分；错题解析与换题型重现；收藏、确认移出；16 题缓冲持续补充，无每日新词上限 |
| 阅读 | 从已学词中选 3–10 个词；到期优先、最多 24 个候选；自备 AI 生成文章、译文和理解题；最新 20 篇离线历史；目标词释义、译文、全文朗读和理解练习 |
| 图表 | 全局学习数、连续天数、分钟；今日到期与首次学习；14 天趋势与日期选择；90 天学习足迹；当前书掌握分布、分档明细与各书进度 |
| 词书 | 43 本、160693 词，沿用当前发布版词书、顺序和 wordId；搜索、分类、切换；当前书单词浏览、收藏和已学筛选 |
| 设置 | 学习偏好；MiniMax、OpenAI、OpenRouter、DeepSeek、BigModel、Moonshot、Ollama 和自定义配置；旧版导入、原生备份、导出、备份后清理；许可与支持链接 |

页面切换保留学习和阅读状态。外观随系统切换；导航、工具栏与交互按钮使用系统控件和适用的 Liquid Glass 样式。卡片额外提供按钮与无障碍操作，不强制使用触控板手势。

## 导入旧版进度

在“设置 → 导入旧版墨书文件夹”中，选择包含以下文件的旧版文档文件夹：

```text
codeword_review_state.json
codeword_activity.json
codeword_user_data.json
codeword_learning_preferences.json
codeword_articles.json
```

旧版沙盒安装的数据通常位于用户资源库中 `Containers/com.codeword.codeword/Data/Documents`；也可以选择用户自行复制出来的这五份文件。应用不会自行扫描旧版容器，也不会读取旧版钥匙串。先备份找到的文件和当前原生进度，再显示导入预览，由用户确认合并。没有文件时给出提示。

原生数据保存在用户“应用程序支持”目录的 `com.codeword.moshu.native` 中。导入、清理前的备份可在设置中打开。导出文件不含 API Key。详细格式、合并规则与兼容性差异见 [MIGRATION.md](MIGRATION.md)。

## AI 和发音

AI 不包含服务额度。预设值沿用旧工程；模型可用性取决于用户自己的服务。MiniMax/Anthropic 使用 Messages 报文，其余使用 OpenAI 兼容聊天报文；本机 Ollama 可不填 Key。远程必须使用 HTTPS，HTTP 仅限回环地址。生成请求只在用户点击后发出。测试连接只 GET 模型目录，部分供应商不提供此接口，失败不等于其生成接口不可用。

API Key 按服务地址隔离存入原生版专用钥匙串服务，不展示明文、不进入进度 JSON、导出、日志或应用包。切换服务不会自动把旧密钥转发到新地址；导入旧学习数据后需自行重新配置密钥。

词音按需请求有道美音并缓存，失败不会算答错或阻止学习；也可点击“系统朗读”使用已安装的系统语音。清理学习数据保留发音缓存。

## 验证与交付范围

本地构建和自动化结果见 [VALIDATION.md](VALIDATION.md)。本轮未使用真实 AI 密钥、未调用收费模型；供应商实连、macOS 26 真机、Intel 构建和公证尚未验证。Mika 的独立集成验收仍是后续环节。

原 Flutter 工程和现有发布流程保留，本 PR 不自动替换商店版本或删除旧版数据。新原生实现与所附 Qwerty Learner 许可见 `Sources/MoshuCore/Resources/THIRD-PARTY.txt` 和 `GPL-3.0.txt`；本目录代码按 GPL-3.0-or-later 提供。
