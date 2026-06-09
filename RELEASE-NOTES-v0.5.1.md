# CodeWord v0.5.1 — 修偏左 + 真 push

> 看了你截图明白了。v0.4.11 那个"push"其实**还在用 AnimatedSwitcher 默认的 fade-out**，所以你看到的是渐隐渐出。而且内容偏左是 padding 太小 + Android edge-to-edge 没吸到 inset。

## 1. 偏左 → 24px padding + 全 body SafeArea

之前 `AppSpacing.x5` = 20px，**在这个 Android 设备上 20px 看着就像贴边**。改成 `AppSpacing.x6` = 24px。

```dart
// 之前
padding: const EdgeInsets.fromLTRB(
  AppSpacing.x5, AppSpacing.x3, AppSpacing.x5, AppSpacing.x4,
),  // progress bar

padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),  // question

padding: const EdgeInsets.fromLTRB(
  AppSpacing.x5, AppSpacing.x3, AppSpacing.x5, AppSpacing.x5,
),  // options

// 现在
AppSpacing.x6 (24) on all three
```

24 是 iOS HIG + Material Design 都接受的安全边距最低值。视觉上**内容明显离屏幕边有呼吸空间**。

## 2. 渐隐渐出 → 自写 `_PushSwitcher`

v0.4.11 的 `AnimatedSwitcher` 即使我把 `transitionBuilder` 改成 slide，**老 child 还是在用 AnimatedSwitcher 默认的 fade-out**。我太天真了——`transitionBuilder` 只 wrap 新 child，老 child 走的是默认 fade。

新写了一个 `_PushSwitcher`（stateful，200ms）：

```dart
class _PushSwitcher extends StatefulWidget {
  final SessionPhase phase;
  final Widget child;
  // ...
}

class _PushSwitcherState extends State<_PushSwitcher>
    with SingleTickerProviderStateMixin {
  // 切换时：把旧 child 存起来 + 启动 200ms AnimationController
  // build:
  //   Stack(
  //     1) 新 child:  Transform.translate(Offset(0.12 * (1-t) * width, 0))  // 从右滑入
  //     2) 旧 child:  Transform.translate(Offset(-0.12 * t * width, 0))     // 滑出左
  //   )
  // 两个 child 都**不透明**，没有任何 FadeTransition
}
```

**全程不透明**。easeOutCubic。200ms。

## 视觉

- 答错 → 旧 asking **滑出左**（位移 = -12% 屏宽）→ 新 wrongDetail **从右滑入**（位移从 +12% 到 0）
- 答对 → 上一题 asking 滑出左 → 下一题 asking 从右滑入
- **没有 fade**、**没有 scale**、**没有 opacity 变化**——只有平移

## 8 测过

无变化（layout / 状态机 / 数据全不动）。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.5.1-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.5.1/codeword-0.5.1-macos.dmg) | 22 MB |
| Android | [app-0.5.1-release.apk](https://github.com/gofenix/codeword/releases/download/v0.5.1/app-0.5.1-release.apk) | 46 MB |

## 装上 v0.5.1 验

1. 进学习流 — 内容**离屏幕边明显有呼吸空间**（24px）
2. 答错一道 — 旧 asking **整体滑出左** → 新 wrongDetail **从右滑入**——**没有 fade**，全程 100% 不透明
3. 答对 — 同上
4. 多切几次 — 完全没有"渐隐"或"抽走"的感觉

挑下一个。
