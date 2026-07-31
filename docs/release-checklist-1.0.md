# 墨书 1.2.30 TestFlight 与 Google Play 内部测试发布门禁

## 自动化门禁

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] iPhone 17 Pro Max / iOS 26.5 核心流程验收
- [ ] 签名 Release IPA 构建与 Xcode Validate App
- [ ] `tools/check_release_secrets.sh <ipa>`
- [ ] `playRelease` AAB 和 `githubRelease` APK 均通过凭据扫描

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

## Google Play

- [ ] `play` 构建不显示 GitHub 更新入口，Manifest 不含 APK 安装权限、FileProvider 或安装查询
- [ ] `github` 构建保留现有 GitHub APK 更新能力
- [ ] Release AAB 使用 `codeword-upload` 证书且签名主体不是 `Android Debug`
- [ ] Play App Signing 已启用，Upload Key 证书已登记
- [ ] versionCode 高于 Play Console 已有构建，target API 满足上传要求
- [ ] 商店资料、Data Safety、内容分级、13 岁以上目标受众和无广告声明已填写
- [ ] 构建上传至“墨书内部测试”，并从 Google Play 完成安装验收
- [ ] 本阶段不创建封闭测试、不提交生产发布
