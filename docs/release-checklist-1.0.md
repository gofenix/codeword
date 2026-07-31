# 墨书 1.2.30 TestFlight 发布门禁

## 自动化门禁

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] iPhone 17 Pro Max / iOS 26.5 核心流程验收
- [ ] 签名 Release IPA 构建与 Xcode Validate App
- [ ] `tools/check_release_secrets.sh <ipa>`

## iOS 发布配置

- [ ] Target 仅支持 iPhone，Bundle ID 为 `com.codeword.codeword`
- [ ] Apple Team、Distribution Certificate 和 Provisioning Profile 有效
- [ ] iOS 不显示或执行 GitHub APK 更新
- [ ] 隐私政策、技术支持和数据来源页面在 App 内可访问
- [ ] GitHub Pages 的 `/privacy/` 与 `/support/` 可公开访问
- [ ] App Store Connect 使用简体中文、SKU `moshu-ios`

## TestFlight

- [ ] 构建号未与 App Store Connect 历史构建冲突
- [ ] 构建处理完成并加入“墨书内部测试”分组
- [ ] 从 TestFlight 安装后完成冷启动、答题切换和发音验证
- [ ] 本阶段不开放外部测试、不提交 App Review
