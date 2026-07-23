enum AiProviderId {
  minimax,
  openai,
  openRouter,
  deepSeek,
  bigModel,
  moonshot,
  ollama,
  custom,
}

class AiProviderPreset {
  final AiProviderId id;
  final String name;
  final String baseUrl;
  final String recommendedModel;
  final bool requiresApiKey;

  const AiProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.recommendedModel,
    this.requiresApiKey = true,
  });

  bool matchesBaseUrl(String value) =>
      baseUrl.isNotEmpty && _normalizeUrl(baseUrl) == _normalizeUrl(value);

  static AiProviderPreset fromBaseUrl(String value) {
    for (final preset in aiProviderPresets) {
      if (preset.matchesBaseUrl(value)) return preset;
    }
    return customAiProviderPreset;
  }
}

const aiProviderPresets = <AiProviderPreset>[
  AiProviderPreset(
    id: AiProviderId.minimax,
    name: 'MiniMax',
    baseUrl: 'https://api.minimaxi.com/anthropic',
    recommendedModel: 'MiniMax-M2.7',
  ),
  AiProviderPreset(
    id: AiProviderId.openai,
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    recommendedModel: 'gpt-5-mini',
  ),
  AiProviderPreset(
    id: AiProviderId.openRouter,
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    recommendedModel: 'openrouter/auto',
  ),
  AiProviderPreset(
    id: AiProviderId.deepSeek,
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    recommendedModel: 'deepseek-v4-flash',
  ),
  AiProviderPreset(
    id: AiProviderId.bigModel,
    name: '智谱 BigModel',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    recommendedModel: 'glm-4.6',
  ),
  AiProviderPreset(
    id: AiProviderId.moonshot,
    name: '月之暗面 Moonshot',
    baseUrl: 'https://api.moonshot.cn/v1',
    recommendedModel: 'kimi-k2.5',
  ),
  AiProviderPreset(
    id: AiProviderId.ollama,
    name: 'Ollama（本地）',
    baseUrl: 'http://localhost:11434/v1',
    recommendedModel: 'llama3.2',
    requiresApiKey: false,
  ),
];

const customAiProviderPreset = AiProviderPreset(
  id: AiProviderId.custom,
  name: '自定义',
  baseUrl: '',
  recommendedModel: '',
);

String _normalizeUrl(String value) {
  var normalized = value.trim().toLowerCase();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
