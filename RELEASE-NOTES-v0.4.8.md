# CodeWord v0.4.8 — 微动效 / 微动画 / 微震动

> 加了克制的微交互,处处是质感。

## 改动 (vs v0.4.7)

加了一组**复用微动效 primitives**（`lib_ui` 里）:

| 组件 | 干啥的 |
|---|---|
| `PressableScale` | 包裹任意 child,按下缩到 0.97 + 透明度 0.85,120ms easeOutCubic 弹回,自带 light haptic |
| `FavoriteStar` | outlined ↔ filled 之间 280ms 转 360° + scale 0.6→1.0 弹跳,easeOutBack |
| `AnimatedContainer` 在 `AppCard` 里 | tappable 卡片颜色 / 阴影属性变化时自动 180ms 平滑过渡 |
| `AnimatedSwitcher` + `SlideTransition` | 学习页 asking ↔ wrongDetail 切换 240ms slide + fade |
| `TweenAnimationBuilder` 在 `ProgressBar` | 进度条 0 → 新值 320ms easeOutCubic 平滑爬 |

## 加了 haptic 反馈（克制版）

| 场景 | 反馈 |
|---|---|
| 答对 | `lightImpact()`（轻微） |
| 答错 | `mediumImpact()`（稍重，告诉用户答错了） |
| 收藏切换 | `lightImpact()` |
| 移除 | `mediumImpact()` |
| 切 tab | `selectionClick()`（原生选择咔哒声） |
| 开始学习 | `lightImpact()` |
| 选项按下 | `PressableScale` 自带 |

没加 iOS UIImpactFeedbackGenerator（没平台 channel 桥），用的是 `HapticFeedback` 抽象层，macOS 用 `NSSound`、Android 用 `HapticFeedbackConstants`。**所有震动都 200ms 内自然衰减，不会"嗡嗡嗡"个不停**。

## 用了的地方

- 学习页 **A/B/C/D 选项** — 按下 scale 0.97 + 透明度 0.85 + 轻 haptic,松手反馈色
- 答错页 **收藏 ⭐ / 移除 🗑️** 按钮 — scale + 收藏星旋转 360°
- 答错页 "记住了下一题" 主按钮 — 卡片整体缩 0.98
- 学习页进度条 — 推进一题时 320ms 平滑爬
- 学习页 asking ↔ wrongDetail 切换 — 240ms slide + fade
- 首页 "开始今日学习" 按钮 — light haptic + 卡片
- 5-tab 底栏切换 — `selectionClick` 原生咔哒
- 所有 `AppCard` 带 onTap 的 — 按下 scale 0.98 + 阴影变化

## 没加（怕过度）

- ❌ Spring bounce / overshoot 弹跳（iOS 风）—— 跟 v5 "cream + 静" 不搭
- ❌ Hero shared element 转场 —— 学习页单词是随机选,跟首页 hero word 不一定同一个
- ❌ Loading skeleton —— 全部是瞬时
- ❌ 数字 count-up —— SM-2 数值跳太快,count-up 看起来假
- ❌ Streak chip pulse —— 没必要
- ❌ Stats heatmap stagger-in —— 实现复杂,首屏也不会重看

## 测过 8 个

boot / start learning / SM-2 / empty stats / real stats / total due / mastery 分类 / 词库进度。**没动 review / vocab 数据模型**,只是包装层加了动效,所以测试无变化。

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.4.8-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.4.8/codeword-0.4.8-macos.dmg) | 22 MB |
| Android | [app-0.4.8-release.apk](https://github.com/gofenix/codeword/releases/download/v0.4.8/app-0.4.8-release.apk) | 46 MB |

## 装上 v0.4.8 验

1. 进学习页,**点 A/B/C/D 任意一个** —— 应该感觉"按下去有反应,松手有反馈"
2. 答错 —— 感觉震动比答对稍重（mediumImpact）
3. 答对 —— 卡片自动滑进下一题,进度条平滑爬
4. 答错 → 看详情 → 点 ⭐ 收藏 —— 星转一圈、变金色、再点转回空心
5. 切 5 个 tab —— 每次都有 selection click 咔哒
6. 点首页 "开始今日学习" —— 卡片缩一下、跳进学习流

挑下一个。
