# CodeWord v0.5.2 — Pulse 上线（类 ChatGPT pulse 的本地版）

> 明白。Pulse 就像 ChatGPT 的 pulse——**一个屏告诉你今天该干嘛**。这是个**纯本地版**（不连 AI API，不传数据），但用你已有 review state + activity + streak 数据给你一个"今日脉搏"。

## 1. Pulse 主页 = 4 块卡片

打开 Pulse tab，**一屏看完今天的所有事**：

```
┌──────────────────────────────┐
│ Pulse                         │
│ 6 月 9 日 · 周一                │
├──────────────────────────────┤
│ 📊 连续 7 天 · 今天别断          │
│   待复习   今日新词   已掌握      │
│    3        0        147      │
│   优先级最高  今天还没学  累计      │
├──────────────────────────────┤
│ 该复习了                  3 个 │
│  overfitting  /ˌəʊvəˈfɪtɪŋ/  逾期 2 天 │
│  dropout      /ˈdrɒp.aʊt/    今天  │
│  momentum     /məˈmentəm/    逾期 1 天 │
│  [    开始    ]                │
├──────────────────────────────┤
│ 推荐新词                  3 个 │
│  algorithm    /ˈælɡərɪðəm/  B1 │
│  bias         /baɪəs/        A2 │
│  epoch        /ˈiːpɒk/       B2 │
│  [    开始    ]                │
├──────────────────────────────┤
│ 🔥 最近 30 天                  │
│   47 次答题 · 5 天活跃          │
│  ▁▂▃▄▅▆█ (5×6 mini heatmap)  │
└──────────────────────────────┘
```

### 块 1：今日焦点（focus card）
- 标题：连续 N 天 · 今天别断 / 回来啦 / 今天还没有开始（看 streak + reviewsToday 决定）
- 3 个 cell：**待复习**（蓝色 info 提示"优先级最高"） / **今日新词**（绿色 primary） / **已掌握**（绿色 success 提示"累计"）
- 不再做 9 字段的复杂 summary，只剩这 3 个最有信息量的数字

### 块 2：该复习了
- **SM-2 dueAt ≤ now 的词**，按逾期天数降序，**取 3 个**
- 每行：词（serif 17px）+ 音标 + 翻译 / 右侧小 pill "今天" / "逾期 N 天"
- 没有待复习 → 文案"现在没有待复习的词"（不再显示"已学完所有词"那种 AI 鸡汤）
- 底部"开始" → 直接进 `LearningSessionScreen(vocabId)`，记忆曲线自动混合

### 块 3：推荐新词
- 从**当前学习率最低 + 还有 unseen 词的 vocab** 里取前 3 个
- 每行：词（serif）+ 音标 + 翻译 / 右侧 CEFR pill (A1-C2)
- 全部学完 → 文案"已学完所有词"
- "开始" → 同上

### 块 4：最近 30 天热力
- 5×6 mini heatmap（30 cells，绿度按 review 数 0/1-5/6-15/16+ 分 4 级）
- 顶部"X 次答题 · Y 天活跃"

## 2. 阅读 tab 仍 placeholder

你说"阅读是 AI 基于当天要学习&复习的，生成的文章"。这是**真 AI feature**，需要 LLM API + BYOK 设置流程。**我没在 v0.5.2 做**——要单独一个 version：
- 加 BYOK 设置入口（flutter_secure_storage 已经接好）
- 加 LLM 调用（OpenAI / Anthropic / 国内 8 家 — 你定）
- 加文章渲染 + 高亮词 hover

> 跟我说一声"上 BYOK + 阅读"，我就开 v0.5.3 干这个。

## 3. 8 测过

无回归。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.5.2-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.5.2/codeword-0.5.2-macos.dmg) | 22 MB |
| Android | [app-0.5.2-release.apk](https://github.com/gofenix/codeword/releases/download/v0.5.2/app-0.5.2-release.apk) | 46 MB |

## 装上 v0.5.2 验

1. **底部 tab 选 Pulse** → 看到日期 + 4 块卡
2. 焦点卡：看到 streak / 待复习 / 今日新词 / 已掌握，**没学的全 0 + "今天还没有开始"**
3. 该复习：如果你用过一阵 app，这儿会有真实词；没用过就是空
4. 推荐新词：永远会有（除非你学完了 9 个 vocab 全部 500 词）
5. 30 天热力：5×6 灰格（没用过）/ 绿格
6. 点"开始" → 跳到 `LearningSessionScreen`，**不是另一个 flow**，是已有的那个

下一步：
- **A.** 上 BYOK + 阅读 tab（AI 生成文章）
- **B.** 加更多 AI 工具（按词查例句、AI 解释错题）
- **C.** 别的设计调整
