# CodeWord v0.6.2 — 修了 wrongDetail 卡缩成"贴左边一条"的问题

> 我能看到截图（其他 agent 看不到）。截图里**真正的 bug**不是 padding 不一致——是 `AppCard` 本身**没有撑满宽度**。

## 截图分析

我打开你的截图看到：
- B/C/D 选项卡：左边缘在 x≈24px（正确，24px padding）
- "diffusion" 详情卡：左边缘在 x≈0px，**内容贴到屏幕最左边**
- "记住了,下一题 →" 红色按钮：左边缘也在 x≈10-15px

## 真正的 root cause

```dart
// 之前
return AppCard(
  padding: const EdgeInsets.all(AppSpacing.x5),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          PillTag.domain(...),
          PillTag.level(...),
        ],
      ),
      const SizedBox(height: AppSpacing.x4),
      Row(
        children: [
          Expanded(child: Text(word.word, ...)),  // ← 关键
          _AudioButton(word: word),
        ],
      ),
      ...
    ],
  ),
);
```

`AppCard` 放在 `Column(crossAxisAlignment: CrossAxisAlignment.start)` 里——**这意味着 AppCard 不会自动撑满父宽度**，而是按内容 intrinsic width 缩。

但里面那个 `Row(children: [Expanded(...), _AudioButton(...)])` 没法 resolve 宽度（Expanded 需要父宽约束才能工作）→ Row 缩到只装下 audio button 40px 宽 → AppCard 整个缩成大约 280px（40px 按钮 + 内容）→ 看起来就像"贴左边一条"。

**v0.6.1 改 padding 没用**，因为问题不是 padding，是 AppCard 自己**没撑满**。

## Fix

```dart
return SizedBox(
  width: double.infinity,  // ← 强制撑满
  child: AppCard(
    padding: const EdgeInsets.all(AppSpacing.x5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [...],
    ),
  ),
);
```

`_HeroWordDetail` 和 `_QuestionPrompt`（asking view 的题卡，**同样的隐患**）都加了。

## 视觉

- 详情卡现在跟 B/C/D 选项卡的左右边缘**完全对齐**（都 24px padding）
- "记住了,下一题 →" 红色按钮**不再偏左**
- 内容（diffusion、phonetic、翻译、例句）整齐地缩进 44px（24 outer + 20 inner card padding）

## 16 测过

无回归。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.6.2-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.6.2/codeword-0.6.2-macos.dmg) | 23 MB |
| Android | [app-0.6.2-release.apk](https://github.com/gofenix/codeword/releases/download/v0.6.2/app-0.6.2-release.apk) | 49 MB |

## 装上 v0.6.2 验

1. 学到第 1 题故意答错
2. 详情卡的左边缘**跟 B/C/D 选项卡左边缘对齐**（都在 x=24）
3. "diffusion" 单词、"例句"、翻译——全都整齐缩进 44px
4. "记住了,下一题 →" 红色按钮**撑满整个内容区**

## 教训（记一下）

`AppCard` 放在 `Column(crossAxisAlignment: start)` 里时，**不会**自动撑满——这是 Flutter 的 layout 规则（start 模式下 Column 不 stretch 子项）。**任何**想撑满的 child 必须显式给 `SizedBox(width: double.infinity, ...)` 或 `width: double.infinity` 在 AppCard 自己上。

下面如果有别的屏也有"贴左一条"的现象，同一个 fix 套上就行。
