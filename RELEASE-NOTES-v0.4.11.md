# CodeWord v0.4.11 — 改 push，hoist 进度条

> 你说得对：v0.4.10 的 cross-fade 期间，进度条会被同时画两次。

## 你看到的问题

v0.4.10 我用了 cross-fade（淡入淡出 + 微 scale），看着是流畅了，但有个**结构性 bug**：

```
Scaffold.body = AnimatedSwitcher
  ├── 旧: _AskingView  ── 内含 _ProgressBar(50%)
  └── 新: _WrongDetailView ── 内含 _ProgressBar(50%)
```

AnimatedSwitcher 默认 **两个 view 同时 render**（旧的在淡出，新的在淡入）。我虽然加了 `layoutBuilder: Stack`，但那个 Stack 是**垂直堆叠**的，两个 progress bar 会在 240ms 过渡里**叠在一起**显示。

看着像"进度条闪了一下"或者"进度条双倍"。**你看得对**。

## 修法（v0.4.11）

### 1. Hoist 进度条出 AnimatedSwitcher

```
Scaffold.body = Column
  ├── _ProgressBar(...)        ← 永远单实例
  └── Expanded(
        AnimatedSwitcher
          ├── 旧: _AskingView     (不再含 progress)
          └── 新: _WrongDetail   (不再含 progress)
      )
```

进度条**只 render 一次**，永远在 body 顶层。AnimatedSwitcher 里只动"主体内容"。

### 2. 换 push 过渡（不再是渐隐渐现）

你明确说"不要搞渐隐渐现"。改成 **push 推入式**：

```dart
transitionBuilder: (child, anim) {
  return SlideTransition(
    position: Tween(begin: Offset(0.08, 0), end: Offset.zero).animate(anim),
    child: SlideTransition(
      position: Tween(begin: Offset.zero, end: Offset(-0.08, 0)).animate(anim),
      child: child,    // ← 不带 FadeTransition，全不透明
    ),
  );
},
```

旧 view **整体滑出左边** 0.08，新 view **从右边滑入** 0.08。**两段都是不透明**，没有"渐隐"那一段。240ms easeOutCubic。

## 现在的视觉

- 答错：旧 asking view 滑出左 → 新 wrongDetail view 滑入右 → 顶 progress bar 一直在那里，**完全不动**
- 答对：上一题 asking view 滑出左 → 下一题 asking view 滑入右
- **没有"抽走"、"渐隐"、"闪"任何一种感觉**

## 8 测过

无变化（进度条 hoist 不动 data layer）。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.11-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.11/codeword-0.4.11-macos.dmg) | 22 MB |
| Android | [app-0.4.11-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.11/app-0.4.11-release.apk) | 46 MB |

## 装上 v0.4.11 验

1. 进学习流
2. 答错一道 — 进度条**应该全程在顶**不闪不跳，body 滑出滑入
3. 答对 — 同上，下一题滑入
4. 多切几次 — 进度条位置**应该一动不动**（不再被 AnimatedSwitcher 渲染两次）

挑下一个。
