# CodeWord v0.4.7 — 丰富统计页

> 7 个新 section,无痛单词风格。收藏 / 移除 / 学习分钟 / 打开次数 / 掌握分布 / 词库进度 / Streak Schedule / Daily Trends / Daily Study Time 全上。

## 改动 (vs v0.4.6)

| 区域 | 之前 | 现在 |
|---|---|---|
| 顶部 3-cell 摘要 | ✅ | 保留(已学过/看过/平均 EF) |
| **掌握分布** | ❌ | ✅ 5 档 horizontal stacked bar + legend(熟悉/认识/模糊/陌生/待学习) |
| **词库进度** | ❌ | ✅ 9 套词库,每套一行 emoji + 进度条 + N / N |
| **今天 6-cell 网格** | 2 个 cell | 6 个 cell:复习/新学/收藏/移除/分钟/打开 |
| **Streak Schedule** | ❌ | ✅ 13 周 × 7 天 网格(90 天热力) |
| **Daily Trends** | 单 heatmap | ✅ 真 14 天 bar chart(答题数) |
| **Daily Study Time** | ❌ | ✅ 真 14 天 bar chart(分钟数) |
| 累计 | ❌ | ✅ "共 N 分钟" 累计卡片 |
| 收藏/移除按钮 | ❌ | ✅ 答错页有 ⭐收藏 / 🗑️移除 按钮 |
| 学习分钟追踪 | ❌ | ✅ LearningSessionScreen init/dispose 记分钟 |

## 7 个新 section 长这样

1. **顶部 3-cell 摘要** — 已学过 / 看过 / 平均 EF
2. **掌握分布** — 一条横向 stacked bar,5 档配色 + 5 个 legend chip
3. **词库进度** — 9 行,emoji + 词库名 + 进度条 + "X / Y 词"
4. **今天** — 6 个 cell 网格:复习 / 新学 / 收藏 / 移除 / 分钟 / 打开
5. **Streak Schedule** — 13 周 × 7 天 90 格,绿=有学习,灰=没学习
6. **Daily Trends** — 14 天答题次数 bar chart
7. **Daily Study Time** — 14 天学习分钟 bar chart
8. **累计** — 累计学习分钟 + 6 条 changelog

## 掌握分布阈值

| 档 | SM-2 条件 |
|---|---|
| 熟悉 (familiar) | EF ≥ 2.5 且 reps ≥ 3 |
| 认识 (recognized) | EF ≥ 2.3 且 reps ≥ 2 |
| 模糊 (vague) | EF ≥ 1.8 且 reps ≥ 1 |
| 陌生 (unfamiliar) | 有 state 但 reps == 0(至少答错过 1 次) |
| 待学习 (unseen) | 完全没看过 |

## 词库进度

每套词库一行:emoji + 词库名 + 进度条 + "已学 X / Y 词"。颜色按词库主题色:
- CS 紫 / Python 蓝 / AI 绿 / LLM 紫 / Web 橙 / 云原生 青 / 数据 粉 / 安全 红 / 产品 紫

## Streak Schedule

仿 GitHub contribution graph 的 13 周 × 7 天 90 格布局,每格一格,绿色 = 当天有学习。颜色:
- 没学习:浅灰
- 有学习:绿色

## Daily Trends & Daily Study Time

自定义 `_Bars` widget,14 天柱子图,最后一根高亮表示"今天"。峰值在右上角小字标出。

## 收藏 / 移除按钮

答错页(wrongDetail)右上角加两个 pill 按钮:
- ⭐ 收藏 — 点一下加进 favorites,再点取消
- 🗑️ 移除 — 加进 removed,直接跳下一题

这两个数据存到 `codeword_user_data.json`(新文件,独立于 review state 和 activity)。

## 学习分钟追踪

`LearningSessionScreen` 在 `initState` 记开始时间,`dispose` 算 elapsed,按整分钟累加到 `codeword_user_data.json:studyMinutes[date]`。

## 打开次数

`main()` 调一次 `ReviewRepository.instance.recordOpen(DateTime.now())`,每次冷启动 +1,存到 `openCounts[date]`。

## 新增本地文件

| 文件 | 内容 |
|---|---|
| `codeword_user_data.json` | favorites / removed / openCounts / studyMinutes |

(3 个文件都在 `getApplicationDocumentsDirectory()`,清 app 数据就全没,符合 local-first。)

## 8 测过

- boot / start learning / SM-2 round-trip
- empty stats / real stats / total due
- mastery distribution places words correctly
- per-vocab progress surfaces all built-in vocabs

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.7-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.7/codeword-0.4.7-macos.dmg) | 22 MB |
| Android | [app-0.4.7-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.7/app-0.4.7-release.apk) | 46 MB |

## 装上 v0.4.7 怎么验

1. 进统计页 — 7 个 section 全展开
2. 跑完一组题(10 题) — "今天" 复习 +N、新学 +M、分钟 +K
3. 答错几道 — 右上角 ⭐ / 🗑️ 按钮可点;点 ⭐ 后回统计页,"收藏" 计数 = 已点的次数
4. 答错点 🗑️ — 自动跳下一题,SnackBar 提示"已移除"
5. Streak Schedule 看到今天那格是绿色
6. Daily Trends 最后一根高亮(今天),其它天浅绿色
7. 退出 app 再开 — "打开" +1,本天 6-cell 网格更新

挑下一个。
