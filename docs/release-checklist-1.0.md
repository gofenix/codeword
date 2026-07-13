# CodeWord 1.0 发布门禁

## 自动化门禁

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter test integration_test -d <device>`
- [ ] `flutter build ios --release --no-codesign`
- [ ] `flutter build appbundle --release`
- [ ] `tools/check_release_secrets.sh <ipa-or-aab>`
- [ ] Coder Core 恰好 500 个唯一词，释义不超过 36 字且例句完整

## 商店与签名

- [ ] App Store Connect 设置为一次性付费下载
- [ ] Google Play 设置为一次性付费下载
- [ ] 配置 Apple Team、Distribution Certificate 和 Provisioning Profile
- [ ] 复制 `android/key.properties.example` 为本地 `key.properties` 并配置 Release Keystore
- [ ] 确认应用图标、启动页、截图、支持邮箱和隐私政策 URL
- [ ] 商店详情明确 AI 阅读需要自备 API Key，模型费用不包含在购买价格中

## 封闭测试

- [ ] 至少 20 名目标用户连续测试 7 天
- [ ] 无崩溃、数据丢失、凭据泄露及 P0/P1 缺陷
- [ ] 至少 80% 完成首轮学习
- [ ] 至少 60% 在 7 天内完成 5 次学习
- [ ] 48 小时后的中位主动回忆正确率不低于 70%
- [ ] 至少 70% 认为核心背词能力值得商店价格

未完成以上门禁时，版本保持封闭测试状态，不公开发布 1.0。
