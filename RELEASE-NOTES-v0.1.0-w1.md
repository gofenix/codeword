# CodeWord v0.1.0-w1 Preview

> 无登录极客背单词 · macOS + Android · Flutter 3.38
> 这是 W1 周（脚手架 + v5 视觉 + AI 核心 100 词）的预览版，仅展示今日页。
> 完整学习流（词库 / 学习 / 复习 / 统计）将在 W2-W4 迭代中补齐。

## 安装

### macOS

1. 下载下方的 `codeword-0.1.0-w1-macos.dmg`（18MB · universal: Intel + Apple Silicon）
2. 双击挂载，把 `CodeWord` 拖入 `Applications`
3. **首次打开**会提示"无法验证开发者"，请：
   - 在 `系统设置 → 隐私与安全性` 找到刚被拦截的 CodeWord，点击**仍要打开**
   - 或在终端执行 `xattr -d com.apple.quarantine /Applications/CodeWord.app`
4. 这是 ad-hoc 签名版（未走 Apple 公证），仅供自测。正式发版会用你的开发者账号公证。

### Android

W2 之后才会产出 APK（CI 还没接入 Android SDK build 环境）。

## 包含什么

- ✅ 今日页 v5 视觉（cream / Lora 衬线 / 绿色 pill / 装饰引号 / 7 天 heatmap）
- ✅ 5-tab 底栏（今日 / 词库 / 复习 / 统计 / 我的），其余 4 tab 是占位
- ✅ 100 词 AI 核心词库（已打包进 app，无需联网）
- ✅ 主题 token（`lib_ui` 包）已锁定
- ✅ SM-2 间隔重复算法 + 5 个单测（脚手架）
- 🚧 学习流 A/B/C/D（W2）
- 🚧 词库 / 复习 / 统计 tab（W2-W3）
- 🚧 6 位同步码 + E2E 加密（W4）

## 已知限制

- 仅 macOS 端，Android 待 W4 统一发版
- ad-hoc 签名，**未 Apple 公证** → 会有 Gatekeeper 拦截
- 占位数据（今日 12 词、连续 7 天）写死在 UI 里，W2 接入真实学习计划
- 截图：[待补]（在 macOS 上 `flutter run` 或装完本 dmg 后截）

## 反馈

有 bug / 视觉建议 → 回 issue：[JEF-3](https://github.com/gofenix/codeword/issues)
或直接在本 release 评论区贴图。
