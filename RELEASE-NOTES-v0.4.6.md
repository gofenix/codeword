# CodeWord v0.4.6 — 真实统计

> 首页 / 统计页 / 复习页的数据全接上本地 review 状态，告别 mock。

## 改动 (vs v0.4.5)

之前首页那几个"今天学 12 个新词 / 连续 7 天"、统计页的"已学过 247 / 看过 500"、还有那个 GitHub 风格 heatmap，**全是写死的 mock**。v0.4.6 全接上 `ReviewRepository` 的真实数据。

## 真实数据流

```
recordAnswer(wordId, quality, now)
    ↓
ReviewStateNotifier
  ├─ 更新 in-memory Map<wordId, ReviewState>
  ├─ ReviewRepository.put() → codeword_review_state.json
  └─ ReviewRepository.recordActivity() → codeword_activity.json  ← 新增

stats() = ReviewStats {
  totalSeen, totalLearned, totalDue,
  newToday, reviewsToday,          ← 今天数据
  streakDays, last7Days,           ← 连续天数 + 7天热力
  averageEasiness                   ← 平均 EF
}
```

新增一份 `codeword_activity.json`（每天一个 key `YYYY-MM-DD`，value 是当天答题次数），用来算：
- **连续天数**：今天 / 昨天有活动就 1，往前一天天查，断在第一个没活动的日子
- **7 天热力**：0 / 1-5 / 6-15 / 16+ 四档颜色

## 首页 (Today) 改了什么

| 字段 | 之前 | 现在 |
|---|---|---|
| "今天学 12 个新词" | 写死 12 | `今天学了 N 个新词`（N = stats.newToday） |
| "今天还没学" | 不存在 | 新增 |
| 连续 7 天 chip | 写死 7 | `连续 N 天`（N = stats.streakDays） |
| 新词 cell | 12 | `stats.newToday` |
| 待复习 cell | 8 | `stats.totalDue` |
| 已掌握 cell | 247 | `stats.totalLearned` |
| 本周学习 heatmap | 写死 [3,2,1,3,3,2,0] | `stats.last7Days`（真实） |
| "已学 14 / 20 词" | 写死 | `本周 N 次答题 · 今日 M` |

## 统计页 (Stats) 改了什么

| 字段 | 之前 | 现在 |
|---|---|---|
| 已学过 | 写死 247 | `stats.totalLearned` |
| 看过 | 写死 500 | `stats.totalSeen` |
| 平均 EF | 写死 2.50 | `stats.averageEasiness` |
| 本周热力 heatmap | Random(42) 假数据 | `stats.last7Days`（真实） |
| "N 次答题" | 看过的词数（不是真实答题数） | 本周 7 天答题数总和 |

## 复习页 (Review) 改了什么

| 字段 | 之前 | 现在 |
|---|---|---|
| 待复习 | 8（mock） | `stats.totalDue` |
| 已学过 | 0（mock） | `stats.totalLearned` |

## 数据持久化

两个本地 JSON 文件，**全部在 `getApplicationDocumentsDirectory()`**：

| 文件 | 内容 |
|---|---|
| `codeword_review_state.json` | 每词 SM-2 状态（EF / interval / repetitions / dueAt / lastReviewedAt） |
| `codeword_activity.json` | 每天答题次数（`YYYY-MM-DD` → count） |

清空 app 数据 → 两份文件没了 → 统计全 0。符合 local-first 原则（**真删就真没，不会云端给你恢复**）。

## 没改的

- 还是 5 测过：boot / start learning / SM-2 / empty stats / real stats / total due
- 没新加词库
- 没新加题型
- 没动 AI 助手 BYOK
- 没动 Apple 公证

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.6-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.6/codeword-0.4.6-macos.dmg) | 22 MB |
| Android | [app-0.4.6-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.6/app-0.4.6-release.apk) | 46 MB |

装上 v0.4.6：
1. 进首页，应该看到"今天还没学,开始吧"（如果你是新装）
2. 点"开始今日学习 · AI 核心"，做几道题
3. 回首页 — 数字应该已经变了（新词 +N，已掌握 +N，heatmap 今日有绿点）
4. 进统计页 — "已学过 / 看过 / 平均 EF" 都是真实数据
5. 跨日：明早再开 app，连续 N 天的 N 会 ≥ 1

挑下一个。
