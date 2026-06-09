import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// User-configurable OpenAI-compatible LLM endpoint. All three fields
/// are stored locally in `flutter_secure_storage` (Keychain on macOS,
/// EncryptedSharedPreferences on Android). The api key never leaves
/// the device until the user explicitly makes a request.
///
/// Compatible with: OpenAI, OpenRouter, DeepSeek, Zhipu (BigModel),
/// Moonshot, Ollama (via /v1), LM Studio, and any other
/// `/chat/completions` style endpoint.
class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  static const empty = LlmConfig(
    baseUrl: '',
    apiKey: '',
    model: '',
  );

  /// Returns true if the user has supplied all three required fields.
  bool get isConfigured =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  /// Show only the first 4 + last 4 of the key, e.g. `sk-a…xyz1`.
  /// Returns the empty string for too-short keys.
  String get maskedKey {
    if (apiKey.length <= 8) return '••••';
    return '${apiKey.substring(0, 4)}…${apiKey.substring(apiKey.length - 4)}';
  }

  LlmConfig copyWith({String? baseUrl, String? apiKey, String? model}) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }

  /// Default endpoint for OpenAI. The user is free to swap it out.
  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  /// Convenience factory for a "first time" config (no key yet).
  static LlmConfig defaults() => const LlmConfig(
        baseUrl: defaultBaseUrl,
        apiKey: '',
        model: defaultModel,
      );
}

/// Pluggable backing store for [LlmConfig]. Production uses
/// `FlutterSecureStorage` (Keychain on macOS, EncryptedSharedPreferences
/// on Android). Tests inject an in-memory implementation.
abstract class LlmConfigBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _FlutterSecureStorageBackend implements LlmConfigBackend {
  final FlutterSecureStorage _storage;
  _FlutterSecureStorageBackend([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory backend for unit tests.
class InMemoryLlmConfigBackend implements LlmConfigBackend {
  final Map<String, String> _store = {};
  @override
  Future<String?> read(String key) async => _store[key];
  @override
  Future<void> write(String key, String value) async => _store[key] = value;
  @override
  Future<void> delete(String key) async => _store.remove(key);
}

/// Persists [LlmConfig] under namespaced keys. Storage keys are
/// prefixed with `codeword_llm_` to avoid collisions with the review-
/// state keys.
class LlmConfigStore {
  static const _kBaseUrl = 'codeword_llm_baseUrl';
  static const _kApiKey = 'codeword_llm_apiKey';
  static const _kModel = 'codeword_llm_model';

  final LlmConfigBackend _backend;
  LlmConfigStore([LlmConfigBackend? backend])
      : _backend = backend ?? _FlutterSecureStorageBackend();

  Future<LlmConfig> read() async {
    try {
      final baseUrl = await _backend.read(_kBaseUrl);
      final apiKey = await _backend.read(_kApiKey);
      final model = await _backend.read(_kModel);
      // If everything is empty/missing, return defaults (preset baseUrl
      // + model so the user just needs to type a key).
      if ((baseUrl == null || baseUrl.isEmpty) &&
          (apiKey == null || apiKey.isEmpty) &&
          (model == null || model.isEmpty)) {
        return LlmConfig.defaults();
      }
      return LlmConfig(
        baseUrl: (baseUrl == null || baseUrl.isEmpty)
            ? LlmConfig.defaultBaseUrl
            : baseUrl,
        apiKey: apiKey ?? '',
        model: (model == null || model.isEmpty)
            ? LlmConfig.defaultModel
            : model,
      );
    } catch (_) {
      return LlmConfig.defaults();
    }
  }

  Future<void> write(LlmConfig config) async {
    await Future.wait([
      _backend.write(_kBaseUrl, config.baseUrl),
      _backend.write(_kApiKey, config.apiKey),
      _backend.write(_kModel, config.model),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _backend.delete(_kBaseUrl),
      _backend.delete(_kApiKey),
      _backend.delete(_kModel),
    ]);
  }
}

// ============================================================================
// LLM client (OpenAI-compatible chat completions)
// ============================================================================

/// One message in a chat completion request.
class LlmMessage {
  final String role; // "system" | "user" | "assistant"
  final String content;
  const LlmMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class LlmChatRequest {
  final String model;
  final List<LlmMessage> messages;
  final double temperature;
  final int? maxTokens;
  const LlmChatRequest({
    required this.model,
    required this.messages,
    this.temperature = 0.4,
    this.maxTokens,
  });

  Map<String, dynamic> toJson() => {
        'messages': [for (final m in messages) m.toJson()],
        'temperature': temperature,
        if (maxTokens != null) 'max_tokens': maxTokens,
        'stream': false,
      };
}

class LlmChatResponse {
  final String content;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;
  const LlmChatResponse({
    required this.content,
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
  });
}

class LlmException implements Exception {
  final String message;
  final int? statusCode;
  LlmException(this.message, {this.statusCode});
  @override
  String toString() => statusCode == null
      ? 'LlmException: $message'
      : 'LlmException($statusCode): $message';
}

/// HTTP transport for OpenAI-compatible chat completions. Pluggable so
/// tests can run without a real network round trip.
abstract class LlmTransport {
  Future<String> postJson({
    required String url,
    required Map<String, String> headers,
    required String body,
  });
}

/// `package:http` backed transport. Default for production builds.
class HttpLlmTransport implements LlmTransport {
  final http.Client _client;
  HttpLlmTransport([http.Client? client]) : _client = client ?? http.Client();

  @override
  Future<String> postJson({
    required String url,
    required Map<String, String> headers,
    required String body,
  }) async {
    final response = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }
}

/// LLM client. Send a [LlmChatRequest], get a [LlmChatResponse] back.
class LlmClient {
  final LlmConfig config;
  final LlmTransport transport;

  LlmClient({required this.config, LlmTransport? transport})
      : transport = transport ?? HttpLlmTransport();

  /// Sends a chat completion request and returns the assistant text.
  /// Throws [LlmException] on any non-2xx response or malformed JSON.
  Future<LlmChatResponse> chat(LlmChatRequest request) async {
    final url = _chatCompletionsUrl(config.baseUrl);
    final body = jsonEncode({
      ...request.toJson(),
      'model': request.model.isNotEmpty ? request.model : config.model,
    });
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };
    final raw = await transport.postJson(url: url, headers: headers, body: body);
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw LlmException('Malformed JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw LlmException('Unexpected response shape: $raw');
    }
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw LlmException('No choices in response: $raw');
    }
    final first = choices.first as Map<String, dynamic>;
    final message = first['message'] as Map<String, dynamic>?;
    final content = (message?['content'] as String?) ?? '';
    final usage = decoded['usage'] as Map<String, dynamic>?;
    return LlmChatResponse(
      content: content,
      promptTokens: (usage?['prompt_tokens'] as num?)?.toInt(),
      completionTokens: (usage?['completion_tokens'] as num?)?.toInt(),
      finishReason: first['finish_reason'] as String?,
    );
  }

  /// Build the chat-completions URL. The user-supplied base URL can
  /// be either:
  ///   - https://api.openai.com/v1            → /chat/completions
  ///   - https://api.openai.com/v1/           → /chat/completions
  ///   - http://localhost:11434/v1            → /chat/completions
  ///   - https://example.com                  → /v1/chat/completions
  static String _chatCompletionsUrl(String baseUrl) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.endsWith('/v1')) b = '$b/v1';
    return '$b/chat/completions';
  }
}
