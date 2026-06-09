# CodeWord v0.4.10 — 过渡动效

> 修复了"切到单词详情卡顿丑"的问题。承认上一版我做得不好。

## 问题

之前 `AnimatedSwitcher` 的代码有两个 bug：

1. **`switchOutCurve: Curves.easeInCubic`** — 这个曲线是"开始慢、结束快"，用作**入场**是错的（用作出场才是对的）。所以旧 view 是**越走越快**地消失，看起来像被"抽走"的，而不是优雅退场。
2. **水平 slide 0.06** — 这个位移太小，看起来不是"过渡"而是"抖动"。再加上 asking view 跟 wrongDetail view 高度差异大，layout 会"卡"一下。

## 现在的过渡

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 320),
  switchInCurve: Curves.easeOutCubic,
  switchOutCurve: Curves.easeOutCubic,  // 修对
  layoutBuilder: (currentChild, previousChildren) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        ...previousChildren,
        ?currentChild,  // 避免 height 跳变
      ],
    );
  },
  transitionBuilder: (child, anim) {
    return FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1.0).animate(anim),
        child: child,
      ),
    );
  },
  ...
)
```

做了什么：

1. **两侧曲线都是 easeOutCubic**（出/入都"开始快、结束慢"，自然减速）
2. **duration 320ms**（之前 240ms，太短觉得急）
3. **去掉水平 slide**，改成 cross-fade + **subtle scale (0.985 → 1.0)** 提起的微动感
4. **`layoutBuilder` + Stack**：新 view 进场时按**两者中更高的**占高度，**不会跳 layout**

视觉上：旧 view 淡出 + 微缩，新 view 淡入 + 微放，**320ms 一气呵成**。

## 测过

8 个测试（含新增一个回归测试：`SessionPhase` 没有 `feedback` 这一相 — 防止以后又有人加回来"画蛇添足"）。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.10-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.10/codeword-0.4.10-macos.dmg) | 22 MB |
| Android | [app-0.4.10-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.10/app-0.4.10-release.apk) | 46 MB |

## 装上 v0.4.10 验

1. 进学习流
2. 答错一道 — 单词详情出来应该是**流畅的提拉感**，不是"卡一下然后跳出来"
3. 答对 — 下一题进来是**流畅的交叉淡入**
4. 多切几次 — 不应该有 layout 跳变、不应该有"抽走"的快速消失感

挑下一个。
