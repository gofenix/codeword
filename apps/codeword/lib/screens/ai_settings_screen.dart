import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/llm_config.dart';

/// User-facing AI configuration page.
///
/// Three fields: Base URL / API Key / Model. Plus a "测试连接" button
/// that fires a 1-token chat completion to confirm the endpoint is
/// reachable. No analytics, no telemetry — failures just show in the
/// UI.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late TextEditingController _baseUrlCtl;
  late TextEditingController _apiKeyCtl;
  late TextEditingController _modelCtl;
  bool _obscureKey = true;
  bool _dirty = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResult; // null = not tested, ok/error message
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(llmConfigProvider);
    _baseUrlCtl = TextEditingController(text: cfg.baseUrl);
    _apiKeyCtl = TextEditingController(text: cfg.apiKey);
    _modelCtl = TextEditingController(text: cfg.model);
    _baseUrlCtl.addListener(_markDirty);
    _apiKeyCtl.addListener(_markDirty);
    _modelCtl.addListener(_markDirty);
    // Sync form fields when the async config load completes (fired from
    // LlmConfigNotifier._load via secure storage). Registered from
    // initState so we get exactly ONE listener per widget lifetime —
    // registering it inside build() would add a new subscriber on every
    // rebuild and leak memory + fire duplicate callbacks.
    ref.listenManual<LlmConfig>(llmConfigProvider, (prev, next) {
      if (!_dirty && _apiKeyCtl.text.isEmpty && next.apiKey.isNotEmpty) {
        _baseUrlCtl.text = next.baseUrl;
        _apiKeyCtl.text = next.apiKey;
        _modelCtl.text = next.model;
      }
    });
  }

  @override
  void dispose() {
    _baseUrlCtl
      ..removeListener(_markDirty)
      ..dispose();
    _apiKeyCtl
      ..removeListener(_markDirty)
      ..dispose();
    _modelCtl
      ..removeListener(_markDirty)
      ..dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    // If the key field is empty, keep the provider's current key
    // (e.g. the fallback key) instead of wiping it.
    final providerCfg = ref.read(llmConfigProvider);
    final cfg = LlmConfig(
      baseUrl: _baseUrlCtl.text.trim().isNotEmpty
          ? _baseUrlCtl.text.trim()
          : providerCfg.baseUrl,
      apiKey: _apiKeyCtl.text.trim().isNotEmpty
          ? _apiKeyCtl.text.trim()
          : providerCfg.apiKey,
      model: _modelCtl.text.trim().isNotEmpty
          ? _modelCtl.text.trim()
          : providerCfg.model,
    );
    try {
      await ref.read(llmConfigProvider.notifier).save(cfg);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _test() async {
    final providerCfg = ref.read(llmConfigProvider);
    final cfg = LlmConfig(
      baseUrl: _baseUrlCtl.text.trim().isNotEmpty
          ? _baseUrlCtl.text.trim()
          : providerCfg.baseUrl,
      apiKey: _apiKeyCtl.text.trim().isNotEmpty
          ? _apiKeyCtl.text.trim()
          : providerCfg.apiKey,
      model: _modelCtl.text.trim().isNotEmpty
          ? _modelCtl.text.trim()
          : providerCfg.model,
    );
    if (!cfg.isConfigured) {
      setState(() {
        _testResult = '请先填写 Base URL、API Key 和 Model';
        _testOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    HapticFeedback.lightImpact();
    final client = LlmClient(config: cfg);
    try {
      final resp = await client.chat(
        LlmChatRequest(
          model: cfg.model,
          maxTokens: 4,
          messages: const [LlmMessage(role: 'user', content: 'hi')],
        ),
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = '连接成功 · 返回 ${resp.content.length} 字符';
        _testOk = true;
      });
      HapticFeedback.mediumImpact();
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = e.statusCode == 401
            ? '鉴权失败 (401) · 检查 API Key'
            : e.statusCode == 404
            ? '路径错误 (404) · 检查 Base URL'
            : '失败 (${e.statusCode ?? '-'}): ${e.message}';
        _testOk = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = '网络错误: $e';
        _testOk = false;
      });
    } finally {
      // Always release the underlying HTTP connection pool — the test
      // client is short-lived. Swallow errors because a failing close
      // shouldn't mask the real test result.
      try {
        client.close();
      } catch (_) {}
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空 AI 配置?'),
        content: const Text('将清空 Base URL、API Key 和 Model。本地数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(llmConfigProvider.notifier).clear();
    final cfg = ref.read(llmConfigProvider);
    _baseUrlCtl.text = cfg.baseUrl;
    _apiKeyCtl.text = cfg.apiKey;
    _modelCtl.text = cfg.model;
    setState(() {
      _dirty = false;
      _testResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: Text(
          'AI 接入',
          style: AppTheme.screenHeader(context: context).copyWith(fontSize: 20),
        ),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Text('保存'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5,
            AppSpacing.x4,
            AppSpacing.x5,
            AppSpacing.x8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IntroCard(),
              const SizedBox(height: AppSpacing.x5),
              _Label('Base URL', hint: 'OpenAI 兼容端点'),
              const SizedBox(height: AppSpacing.x2),
              _Field(
                controller: _baseUrlCtl,
                hint: 'https://api.minimaxi.com/anthropic',
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: AppSpacing.x4),
              _Label('API Key', hint: '存到本机 Keychain / 加密 SharedPreferences'),
              const SizedBox(height: AppSpacing.x2),
              _Field(
                controller: _apiKeyCtl,
                hint: 'sk-...',
                obscure: _obscureKey,
                autocorrect: false,
                enableSuggestions: false,
                suffix: IconButton(
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.of(context).inkMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              _Label('Model', hint: '默认 MiniMax-M3，可改'),
              const SizedBox(height: AppSpacing.x2),
              _Field(
                controller: _modelCtl,
                hint: 'MiniMax-M3',
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: AppSpacing.x5),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('测试连接'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.x3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  OutlinedButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x4,
                        vertical: AppSpacing.x3,
                      ),
                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.4),
                      ),
                      foregroundColor: AppColors.danger,
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: AppSpacing.x4),
                _TestResultCard(ok: _testOk, message: _testResult!),
              ],
              const SizedBox(height: AppSpacing.x5),
              _CompatList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.primarySoft,
      shadow: AppShadows.none,
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(
              'Key 只存本机加密存储，不上传服务器。请求直发到 Base URL。',
              style: AppTheme.mutedCaption(
                size: 13,
                color: AppColors.ink,
              ).copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final String? hint;
  const _Label(this.text, {this.hint});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: AppTheme.cardTitle(
            context: context,
          ).copyWith(fontSize: 13, letterSpacing: 0.3),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint!, style: AppTheme.mutedCaption(size: 11, context: context)),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool enableSuggestions;
  final Widget? suffix;

  const _Field({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      style: AppTheme.code(size: 15, color: AppColors.of(context).ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.code(
          size: 15,
          color: AppColors.of(context).inkSubtle,
        ).copyWith(fontWeight: FontWeight.w400),
        filled: true,
        fillColor: AppColors.of(context).surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(
            color: AppColors.of(context).inkSubtle.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(
            color: AppColors.of(context).inkSubtle.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        suffixIcon: suffix,
      ),
    );
  }
}

class _TestResultCard extends StatelessWidget {
  final bool ok;
  final String message;
  const _TestResultCard({required this.ok, required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: ok
          ? AppColors.success.withValues(alpha: 0.10)
          : AppColors.danger.withValues(alpha: 0.08),
      shadow: AppShadows.none,
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            color: ok ? AppColors.success : AppColors.danger,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(
              message,
              style: AppTheme.rowTitle().copyWith(
                fontSize: 13,
                color: ok ? AppColors.success : AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompatList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('兼容', style: AppTheme.sectionLabel(context: context)),
        const SizedBox(height: AppSpacing.x2),
        ..._compatRows.map((r) => _CompatRow(name: r.$1, base: r.$2)),
      ],
    );
  }

  static const _compatRows = <(String, String)>[
    ('OpenAI', 'https://api.openai.com/v1'),
    ('OpenRouter', 'https://openrouter.ai/api/v1'),
    ('DeepSeek', 'https://api.deepseek.com/v1'),
    ('MiniMax', 'https://api.minimaxi.com/anthropic'),
    ('智谱 BigModel', 'https://open.bigmodel.cn/api/paas/v4'),
    ('月之暗面 Moonshot', 'https://api.moonshot.cn/v1'),
    ('Ollama (本地)', 'http://localhost:11434/v1'),
  ];
}

class _CompatRow extends StatelessWidget {
  final String name;
  final String base;
  const _CompatRow({required this.name, required this.base});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              name,
              style: AppTheme.rowTitle(context: context).copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              base,
              style: AppTheme.code(
                size: 11,
                color: AppColors.of(context).inkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
