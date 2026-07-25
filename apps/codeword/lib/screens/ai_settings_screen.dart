import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../models/ai_provider_preset.dart';
import '../state/llm_config.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late final TextEditingController _baseUrlCtl;
  late final TextEditingController _apiKeyCtl;
  late final TextEditingController _modelCtl;

  late LlmConfig _savedConfig;
  late AiProviderPreset _selectedProvider;
  bool _obscureKey = true;
  bool _advancedExpanded = false;
  bool _dirty = false;
  bool _syncingForm = false;
  bool _submitting = false;
  bool _allowPop = false;
  String? _apiKeyError;
  String? _modelError;
  String? _endpointError;
  String? _generalError;

  @override
  void initState() {
    super.initState();
    _savedConfig = ref.read(llmConfigProvider);
    _selectedProvider = AiProviderPreset.fromBaseUrl(_savedConfig.baseUrl);
    _baseUrlCtl = TextEditingController(text: _savedConfig.baseUrl);
    _apiKeyCtl = TextEditingController(text: _savedConfig.apiKey);
    _modelCtl = TextEditingController(text: _savedConfig.model);
    _baseUrlCtl.addListener(_onBaseUrlChanged);
    _apiKeyCtl.addListener(_onDraftChanged);
    _modelCtl.addListener(_onDraftChanged);
    ref.listenManual<LlmConfig>(llmConfigProvider, (previous, next) {
      if (!_dirty && !_submitting) _syncFromConfig(next);
    });
  }

  @override
  void dispose() {
    _baseUrlCtl
      ..removeListener(_onBaseUrlChanged)
      ..dispose();
    _apiKeyCtl
      ..removeListener(_onDraftChanged)
      ..dispose();
    _modelCtl
      ..removeListener(_onDraftChanged)
      ..dispose();
    super.dispose();
  }

  LlmConfig get _draftConfig => LlmConfig(
    baseUrl: _baseUrlCtl.text.trim(),
    apiKey: _selectedProvider.requiresApiKey
        ? _apiKeyCtl.text.trim()
        : 'ollama',
    model: _modelCtl.text.trim(),
  );

  bool _sameConfig(LlmConfig a, LlmConfig b) =>
      a.baseUrl.trim() == b.baseUrl.trim() &&
      a.apiKey.trim() == b.apiKey.trim() &&
      a.model.trim() == b.model.trim();

  void _syncFromConfig(LlmConfig config) {
    _syncingForm = true;
    _savedConfig = config;
    _selectedProvider = AiProviderPreset.fromBaseUrl(config.baseUrl);
    _setText(_baseUrlCtl, config.baseUrl);
    _setText(_apiKeyCtl, config.apiKey);
    _setText(_modelCtl, config.model);
    _syncingForm = false;
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _advancedExpanded = _selectedProvider.id == AiProviderId.custom;
      _clearErrors();
    });
  }

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _onBaseUrlChanged() {
    if (_syncingForm) return;
    final matched = AiProviderPreset.fromBaseUrl(_baseUrlCtl.text);
    if (matched.id != _selectedProvider.id) {
      setState(() => _selectedProvider = matched);
    }
    _refreshDirty();
  }

  void _onDraftChanged() {
    if (_syncingForm) return;
    _refreshDirty();
  }

  void _refreshDirty() {
    final next = !_sameConfig(_draftConfig, _savedConfig);
    if (next == _dirty && _generalError == null) return;
    setState(() {
      _dirty = next;
      _generalError = null;
      _apiKeyError = null;
      _modelError = null;
      _endpointError = null;
    });
  }

  void _clearErrors() {
    _apiKeyError = null;
    _modelError = null;
    _endpointError = null;
    _generalError = null;
  }

  Future<void> _chooseProvider() async {
    if (_submitting) return;
    final selected = await showModalBottomSheet<AiProviderPreset>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ProviderSheet(selected: _selectedProvider),
    );
    if (!mounted || selected == null || selected.id == _selectedProvider.id) {
      return;
    }
    _syncingForm = true;
    _selectedProvider = selected;
    _setText(_baseUrlCtl, selected.baseUrl);
    _setText(_modelCtl, selected.recommendedModel);
    _setText(_apiKeyCtl, selected.requiresApiKey ? '' : 'ollama');
    _syncingForm = false;
    setState(() {
      _advancedExpanded = selected.id == AiProviderId.custom;
      _clearErrors();
      _dirty = !_sameConfig(_draftConfig, _savedConfig);
    });
  }

  bool _validateDraft() {
    final config = _draftConfig;
    final keyError = _selectedProvider.requiresApiKey && config.apiKey.isEmpty
        ? '请输入 API Key'
        : null;
    final modelError = config.model.isEmpty ? '请输入模型名称' : null;
    String? endpointError;
    if (config.baseUrl.isEmpty) {
      endpointError = '请输入 Base URL';
    } else if (!config.hasSafeEndpoint) {
      endpointError = '远程地址必须使用 HTTPS；HTTP 仅允许本机服务';
    }
    setState(() {
      _apiKeyError = keyError;
      _modelError = modelError;
      _endpointError = endpointError;
      _generalError = null;
      if (endpointError != null) _advancedExpanded = true;
    });
    return keyError == null && modelError == null && endpointError == null;
  }

  Future<void> _verifyAndSave() async {
    if (_submitting || !_validateDraft()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final draft = _draftConfig;
    setState(() {
      _submitting = true;
      _clearErrors();
    });
    HapticFeedback.lightImpact();
    try {
      await ref.read(llmConfigVerifierProvider)(draft);
    } on LlmException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (error.statusCode == 401 || error.statusCode == 403) {
          _apiKeyError = '鉴权失败，请检查 API Key';
        } else if (error.statusCode == 404) {
          _endpointError = '服务地址或模型不存在，请检查配置';
          _advancedExpanded = true;
        } else {
          _generalError = '连接失败，请稍后重试';
        }
      });
      return;
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _generalError = '连接超时，请检查网络或服务地址';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _generalError = '网络连接失败，请检查网络后重试';
      });
      return;
    }

    try {
      await ref.read(llmConfigProvider.notifier).save(draft);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _generalError = '连接成功，但配置保存失败，请重试';
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _allowPop = true;
    Navigator.of(context).pop(true);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('放弃未保存的更改？'),
        content: const Text('当前修改尚未验证和保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃更改'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _handleBlockedPop() async {
    if (_submitting || !await _confirmDiscard() || !mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _clearConfiguration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('清空 AI 配置？'),
        content: const Text('将移除服务地址、API Key 和模型，本地学习数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(llmConfigProvider.notifier).clear();
      if (!mounted) return;
      _syncFromConfig(ref.read(llmConfigProvider));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('清空失败，原配置未改变')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final savedProvider = AiProviderPreset.fromBaseUrl(_savedConfig.baseUrl);
    return PopScope<bool>(
      canPop: _allowPop || (!_dirty && !_submitting),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBlockedPop();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: GlassAppBar(
          title: 'AI 阅读',
          titleStyle: AppTheme.screenHeader(
            context: context,
          ).copyWith(fontSize: 20),
          leading: IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.primary,
          ),
          actions: [
            if (_savedConfig.isConfigured)
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'clear') _clearConfiguration();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppColors.danger),
                        SizedBox(width: AppSpacing.x3),
                        Text('清空配置', style: TextStyle(color: AppColors.danger)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x6,
                    AppSpacing.x5,
                    AppSpacing.x6,
                    AppSpacing.x8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_savedConfig.isConfigured) ...[
                        _ConnectionStatus(
                          dirty: _dirty,
                          providerName: savedProvider.name,
                        ),
                        const SizedBox(height: AppSpacing.x6),
                      ],
                      const _FieldLabel('服务商'),
                      const SizedBox(height: AppSpacing.x2),
                      _ProviderSelector(
                        provider: _selectedProvider,
                        onTap: _chooseProvider,
                      ),
                      if (_selectedProvider.requiresApiKey) ...[
                        const SizedBox(height: AppSpacing.x6),
                        const _FieldLabel('API Key'),
                        const SizedBox(height: AppSpacing.x2),
                        _ConfigField(
                          controller: _apiKeyCtl,
                          hintText: '输入你的 ${_selectedProvider.name} API Key',
                          obscureText: _obscureKey,
                          enableSuggestions: false,
                          autocorrect: false,
                          suffixIcon: IconButton(
                            tooltip: _obscureKey ? '显示 API Key' : '隐藏 API Key',
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          errorText: _apiKeyError,
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        const _PrivacyHint(),
                      ] else ...[
                        const SizedBox(height: AppSpacing.x6),
                        const _OllamaKeyHint(),
                      ],
                      const SizedBox(height: AppSpacing.x6),
                      const _FieldLabel('Model'),
                      const SizedBox(height: AppSpacing.x2),
                      _ConfigField(
                        controller: _modelCtl,
                        hintText: '输入模型名称',
                        enableSuggestions: false,
                        autocorrect: false,
                        suffixIcon: const Icon(Icons.edit_outlined, size: 19),
                        errorText: _modelError,
                      ),
                      const SizedBox(height: AppSpacing.x6),
                      Divider(color: palette.divider, height: 1),
                      _AdvancedSettings(
                        expanded: _advancedExpanded,
                        onToggle: () => setState(
                          () => _advancedExpanded = !_advancedExpanded,
                        ),
                        field: _ConfigField(
                          controller: _baseUrlCtl,
                          hintText: 'https://api.example.com/v1',
                          keyboardType: TextInputType.url,
                          enableSuggestions: false,
                          autocorrect: false,
                          errorText: _endpointError,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _SubmitArea(
                error: _generalError,
                submitting: _submitting,
                onPressed: _verifyAndSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  final bool dirty;
  final String providerName;

  const _ConnectionStatus({required this.dirty, required this.providerName});

  @override
  Widget build(BuildContext context) {
    final color = dirty ? AppColors.warning : AppColors.success;
    return Row(
      children: [
        Icon(
          dirty ? Icons.info_outline_rounded : Icons.check_circle_outline,
          color: color,
          size: 20,
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: Text(
            dirty ? '更改尚未生效' : '已连接到 $providerName',
            style: AppTheme.rowTitle(
              context: context,
            ).copyWith(fontSize: 14, color: color),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.cardTitle(context: context).copyWith(fontSize: 15),
  );
}

class _ProviderSelector extends StatelessWidget {
  final AiProviderPreset provider;
  final VoidCallback onTap;

  const _ProviderSelector({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(color: palette.divider),
      ),
      child: InkWell(
        key: const ValueKey('ai-provider-selector'),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x4,
          ),
          child: Row(
            children: [
              Icon(
                _providerIcon(provider.id),
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(
                  provider.name,
                  style: AppTheme.rowTitle(context: context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Icon(Icons.expand_more_rounded, color: palette.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? errorText;

  const _ConfigField({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.suffixIcon,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      keyboardType: keyboardType,
      style: AppTheme.code(size: 15, color: palette.ink),
      decoration: InputDecoration(
        hintText: hintText,
        errorText: errorText,
        filled: true,
        fillColor: palette.surface,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _PrivacyHint extends StatelessWidget {
  const _PrivacyHint();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.lock_outline_rounded,
        size: 17,
        color: AppColors.of(context).inkMuted,
      ),
      const SizedBox(width: AppSpacing.x2),
      Expanded(
        child: Text(
          'API Key 加密保存在本机，仅用于向所选服务商发起请求。',
          style: AppTheme.mutedCaption(
            size: 12,
            context: context,
          ).copyWith(height: 1.45),
        ),
      ),
    ],
  );
}

class _OllamaKeyHint extends StatelessWidget {
  const _OllamaKeyHint();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.lan_outlined, size: 19, color: AppColors.primary),
      const SizedBox(width: AppSpacing.x2),
      Expanded(
        child: Text(
          'Ollama 无需 API Key，仅支持本机 HTTP 地址。',
          style: AppTheme.mutedCaption(size: 13, context: context),
        ),
      ),
    ],
  );
}

class _AdvancedSettings extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final Widget field;

  const _AdvancedSettings({
    required this.expanded,
    required this.onToggle,
    required this.field,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Column(
      children: [
        InkWell(
          key: const ValueKey('ai-advanced-toggle'),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: palette.inkMuted,
                  size: 21,
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('高级设置', style: AppTheme.rowTitle(context: context)),
                      const SizedBox(height: 2),
                      Text(
                        'Base URL',
                        style: AppTheme.mutedCaption(
                          size: 12,
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.chevron_right_rounded,
                  color: palette.inkMuted,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.x4),
                  child: field,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SubmitArea extends StatelessWidget {
  final String? error;
  final bool submitting;
  final VoidCallback onPressed;

  const _SubmitArea({
    required this.error,
    required this.submitting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.x6,
          AppSpacing.x3,
          AppSpacing.x6,
          AppSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.danger,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Text(
                      error!,
                      style: AppTheme.mutedCaption(
                        size: 12,
                        color: AppColors.danger,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('ai-verify-save'),
                onPressed: submitting ? null : onPressed,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.verified_user_outlined, size: 19),
                label: Text(submitting ? '正在验证' : '验证并保存'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderSheet extends StatelessWidget {
  final AiProviderPreset selected;

  const _ProviderSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final providers = [...aiProviderPresets, customAiProviderPreset];
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x6,
              AppSpacing.x2,
              AppSpacing.x6,
              AppSpacing.x3,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择服务商',
                style: AppTheme.cardTitle(
                  context: context,
                ).copyWith(fontSize: 20),
              ),
            ),
          ),
          Divider(height: 1, color: palette.divider),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
              itemCount: providers.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                indent: AppSpacing.x6,
                color: palette.divider,
              ),
              itemBuilder: (context, index) {
                final provider = providers[index];
                final isSelected = provider.id == selected.id;
                return ListTile(
                  key: ValueKey('ai-provider-${provider.id.name}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x6,
                    vertical: AppSpacing.x1,
                  ),
                  leading: Icon(
                    _providerIcon(provider.id),
                    color: isSelected ? AppColors.primary : palette.inkMuted,
                  ),
                  title: Text(
                    provider.name,
                    style: AppTheme.rowTitle(context: context),
                  ),
                  subtitle: provider.id == AiProviderId.custom
                      ? const Text('填写任意 OpenAI 兼容端点')
                      : Text(provider.recommendedModel),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.pop(context, provider),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

IconData _providerIcon(AiProviderId id) => switch (id) {
  AiProviderId.minimax => Icons.graphic_eq_rounded,
  AiProviderId.openai => Icons.hub_outlined,
  AiProviderId.openRouter => Icons.alt_route_rounded,
  AiProviderId.deepSeek => Icons.water_rounded,
  AiProviderId.bigModel => Icons.auto_awesome_outlined,
  AiProviderId.moonshot => Icons.nightlight_outlined,
  AiProviderId.ollama => Icons.lan_outlined,
  AiProviderId.custom => Icons.code_rounded,
};
