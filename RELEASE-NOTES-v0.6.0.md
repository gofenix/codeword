# CodeWord v0.6.0 — AI 接入 + 阅读 tab 上线

> 按你说的：兼容 OpenAI 风格，用户自填 **Base URL / API Key / Model**，**本机加密存**。`POST {base_url}/chat/completions` + `Authorization: Bearer <key>`，跟 OpenAI / OpenRouter / DeepSeek / 智谱 / 月之暗面 / Ollama / LM Studio 全部兼容。

## 1. 新 tab：阅读（AI 生成短文）

不再是 placeholder。真功能：

1. 打开「阅读」tab → 自动从 `ReviewStateNotifier` 拉**今日 5 待复习 + 5 推荐新词**（去重），展示为绿色 pill 词表
2. 点"生成文章" → POST 到你配的 LLM，系统 prompt 是：
   > "You are a writing assistant for a vocabulary app. Write short, engaging English articles for programmers and AI practitioners. Use the supplied target words naturally."
   
   用户 prompt：`Theme: AI / 机器学习. Target words: overfitting, dropout, momentum, ... Constraints: 180-260 words. One paragraph. No bullet points. No headings. Tone: a senior engineer explaining a concept to a junior over coffee.`
3. 文章渲染时**自动高亮**所有目标词（支持 -s/-ed/-ing 词形变化，比如 algorithm → algorithms/algorithmic），底色 `primarySoft`，文字 `primaryDark` 加粗
4. 底部小词表：每行 `word  翻译` 复习用
5. 点 ↻ 重新生成

**关键**：**请求只带词 ID 列表 + 词本身**（不是 review state 整个 JSON）。服务器只知道"用户在背这 8 个词"，不知道 EF、reps、streak 那些隐私数据。

## 2. 「我的」→ AI 接入 → 设置页

顶部 AppBar + 「保存」按钮（dirty 才出现）。3 个字段：

| 字段 | 默认 | 说明 |
|---|---|---|
| **Base URL** | `https://api.openai.com/v1` | 自动补 `/v1`（写 `http://localhost:11434` 也能用） |
| **API Key** | 空 | `••••` 遮蔽，点眼睛切换 |
| **Model** | `gpt-4o-mini` | 任意 OpenAI 兼容 model 名 |

**所有字段**通过 `flutter_secure_storage` 存：
- macOS：Keychain（应用专属沙箱）
- Android：EncryptedSharedPreferences（AES-256 GCM）
- **永不**写任何普通文件、**永不**进日志、**永不**上传

底部还列了 6 个常见 base URL（OpenAI / OpenRouter / DeepSeek / 智谱 / 月之暗面 / Ollama 本地），点不了（一键填表这个我下个版本加，先让你看看格式）。

### 「测试连接」按钮

不写任何 review state，只发一个 1-token 的最小请求：
```
POST {base_url}/v1/chat/completions
Authorization: Bearer sk-...
{ "model": "m", "messages": [{"role":"user","content":"hi"}], "max_tokens": 4, "stream": false }
```

返回 200 → 绿卡 "连接成功 ✓  返回 N 字符" + 中等 haptic
返回 401 → 红卡 "鉴权失败 (401) · 检查 API Key"
返回 404 → 红卡 "路径错误 (404) · 检查 Base URL"
其他 → 红卡 "失败 (code): body"

「清空」按钮 → 弹确认 → key 全部清掉，回到默认 base url + default model（key 空）。

## 3. 架构

| 文件 | 干啥 |
|---|---|
| `packages/lib_core/lib/src/llm_client.dart` | `LlmConfig` / `LlmConfigStore` / `LlmMessage` / `LlmChatRequest` / `LlmChatResponse` / `LlmException` / `LlmTransport` (abstract) / `HttpLlmTransport` (default) / `LlmClient` |
| `apps/codeword/lib/state/llm_config.dart` | `LlmConfigNotifier` (Riverpod StateNotifier) + `llmConfigProvider` + `llmClientProvider` + `llmConfiguredProvider` |
| `apps/codeword/lib/screens/ai_settings_screen.dart` | 设置表单 + 测试连接 + 清空 |
| `apps/codeword/lib/screens/reading_screen.dart` | 阅读 tab 主屏 |
| `apps/codeword/lib/screens/me_screen.dart` | 顶部加了「AI 接入」row，subtitle 实时显示 `model · sk-…xxxx`，已配/未配两种状态 |

**依赖**：`lib_core` 加了 `flutter_secure_storage: ^9.2.2` 和 `http: ^1.2.2`。

**安全契约**（在代码注释里也写了）：
- key 只走 `flutter_secure_storage`
- 不进任何 JSON 文件
- 不进日志
- 不进 `ReviewRepository` 那 3 个文件
- 不上传任何 review state（**只**带当天 8-10 个词 ID）

## 4. 16 测过（新增 8 个 LLM 测）

- `LlmConfig.isConfigured` 3 字段全在才 true
- `LlmConfig.maskedKey` 短 key 走 `••••`，长 key 走 `sk-a…4455`
- `LlmClient` URL 拼接：3 种 base URL 形态都跑通
- `LlmClient` 带 `Authorization: Bearer` + Content-Type + 流式关闭
- `LlmClient` request.model 空时回退到 config.model
- `LlmClient` 4xx 抛 `LlmException(statusCode)`
- `LlmClient` 烂 JSON 抛 `LlmException`（包装 FormatException）
- `LlmConfigStore` 用 `InMemoryLlmConfigBackend` 跑 round-trip

## 下载

| 平台 | 链接 | 大小 |
|---|---|---|
| macOS | [codeword-0.6.0-macos.dmg](https://github.com/gofenix/codeword/releases/download/v0.6.0/codeword-0.6.0-macos.dmg) | 23 MB |
| Android | [app-0.6.0-release.apk](https://github.com/gofenix/codeword/releases/download/v0.6.0/app-0.6.0-release.apk) | 49 MB |

## 装上 v0.6.0 验

1. **底部 tab 选 阅读** → 看到「今日词表」(可能空，先去学几轮)
2. 点「我的」 → 看到「AI 接入」row
3. 点 → 进设置页 → 填 Base URL / API Key / Model → 测试连接
4. 回到「阅读」tab → 点「生成文章」 → 3-5 秒后看到 ~200 词文章，目标词高亮
5. 验 key 不在本地明文：`cat /Users/fenix/Library/Containers/com.example.codeword/Data/Library/Application\ Support/codeword/*.json 2>/dev/null` → 应该看不到 key（Keychain 单独存）

> **没真 key 也能用 app**。AI 相关功能（阅读生成）失败的话就是「去设置 AI」按钮带你去填。其它全部学习流程不受影响。

## 下一步候选

- **A.** 「按词查例句」按钮（每个词详情卡里加，AI 给 3 条例句 + 翻译）
- **B.** AI 解释错题（wrongDetail 屏加 "为什么" 按钮，AI 解释为啥这是对的）
- **C.** 别的设计调整

跟我说一声。
