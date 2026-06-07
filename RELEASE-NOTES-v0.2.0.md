# CodeWord v0.2.0 — V1 (thin slice)

> 无登录极客背单词 · macOS + Android · Flutter 3.38
> **V1 第一个能跑能学**的版本：4 套词库 200 词 + A/B/C/D 学习流 + SM-2 间隔重复。

## 这次新增（vs v0.1.0-w1）

| 模块 | 状态 | 备注 |
|---|---|---|
| **A/B/C/D 看词选义 学习流** | ✅ | 200ms 反馈、答对/答错、4 选 1 |
| **distractor 生成器** | ✅ | 同词库随机 3 个错位选项 |
| **SM-2 接入** | ✅ | 每次答完即时调度，map in-memory |
| **词库 tab** | ✅ | 9 套卡片网格，已上线 4 套高亮 |
| **复习 tab** | ✅ | 待复习 / 已学过 计数 + 空态 |
| **统计 tab** | ✅ | 已学过 / 看过 / 平均 EF + heatmap |
| **我的 tab** | ✅ | 用户卡 + 同步码占位（W4） |
| **CS / Python / Web 三套新词库** | ✅ | 各 50 词，AI 仍是 100 词 |
| **学习完成页** | ✅ | 正确率 + emoji + 收尾 |
| 6 位同步码 + E2E 加密 | 🚧 W4 | UI 占位已加 |
| Android APK | 🚧 W4 | 本机没 SDK |
| 看义选词 / 听音选义 / 看语境选词 / 拼写 | 🚧 W2-W3 | 暂时只接 1 种题型 |

**总计：4 套词库 200 词 · 1 种题型 · SM-2 真实调度 · 5 tab 全实装**

## 安装

```bash
open https://github.com/gofenix/codeword/releases/download/v0.2.0/codeword-0.2.0-macos.dmg
```

挂载 → 拖入 Applications → 首次打开被 Gatekeeper 拦：
- `系统设置 → 隐私与安全性` → 仍要打开
- 或 `xattr -d com.apple.quarantine /Applications/CodeWord.app`

## 怎么玩

1. **今日** tab 点"开始今日学习 · AI 核心" → 进学习流
2. 看英文单词，从 A/B/C/D 4 个中文释义里选一个
3. 200ms 后反馈：✅ 绿对 / ❌ 红错 + 正确答案
4. 答完 10 题 → 总结页（正确率 + emoji）
5. **词库** tab 可以切到 CS / Python / Web
6. **复习** tab 看已学过多少 + 待复习
7. **统计** tab 看 EF / heatmap
8. **我的** tab 同步码占位（W4 出）

数据目前是 in-memory，重启 app 会清空（drift 持久化 W3）。

## 数据 / 同步

- 复习状态：进程内 Map<String, ReviewState>（重启清空，W3 上 drift）
- 词库：JSON 打进 app，无需联网
- 同步：占位（6 位码 + E2E 加密 W4）

## 反馈

有 bug / 视觉 / 交互问题 → 回 issue：[JEF-3](https://github.com/gofenix/codeword/issues)
或在本 release 评论区贴图。
