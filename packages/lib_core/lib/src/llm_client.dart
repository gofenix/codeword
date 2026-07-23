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

  static const empty = LlmConfig(baseUrl: '', apiKey: '', model: '');

  /// Returns true if the user has supplied all three required fields.
  bool get isConfigured =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  /// API keys may only travel over TLS. Plain HTTP is allowed solely for a
  /// loopback model such as Ollama running on the same device.
  bool get hasSafeEndpoint {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (uri.scheme.toLowerCase() == 'https') return true;
    if (uri.scheme.toLowerCase() != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

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

  /// Default endpoint for MiniMax (Anthropic-compatible format).
  static const defaultBaseUrl = 'https://api.minimaxi.com/anthropic';
  static const defaultModel = 'MiniMax-M2.7';

  /// Convenience factory for a "first time" config (no key yet).
  static LlmConfig defaults() =>
      const LlmConfig(baseUrl: defaultBaseUrl, apiKey: '', model: defaultModel);
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
///
/// Reads and writes are serial — `read()` is called once per notifier
/// lifetime, so this is not a perf concern. Serialising avoids the
/// "baseUrl written successfully, apiKey written half-way → partial
/// state on restart" tearing that `Future.wait([x, y, z])` would cause.
class LlmConfigStore {
  static const _kBaseUrl = 'codeword_llm_baseUrl';
  static const _kApiKey = 'codeword_llm_apiKey';
  static const _kModel = 'codeword_llm_model';

  final LlmConfigBackend _backend;
  LlmConfigStore([LlmConfigBackend? backend])
      : _backend = backend ?? _FlutterSecureStorageBackend();

  Future<LlmConfig> read() async {
    // Serial reads so a backend-level error surfaces early.
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
      model: (model == null || model.isEmpty) ? LlmConfig.defaultModel : model,
    );
  }

  /// Serial writes — on failure, none/some of the writes may have
  /// succeeded. The calling [LlmConfigNotifier.save] treats ANY
  /// failure as a full failure and does not update the in-memory
  /// state, so on restart storage and memory will re-converge via
  /// [read] (at worst a partial write at the storage level is
  /// normalised back into sensible defaults by the logic above).
  Future<void> write(LlmConfig config) async {
    await _backend.write(_kBaseUrl, config.baseUrl);
    await _backend.write(_kApiKey, config.apiKey);
    await _backend.write(_kModel, config.model);
  }

  Future<void> clear() async {
    await _backend.delete(_kBaseUrl);
    await _backend.delete(_kApiKey);
    await _backend.delete(_kModel);
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
        'model': model,
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

  /// Release any held resources (e.g. an HTTP client pool). Must be
  /// synchronous — Riverpod's `ref.onDispose` callback takes a
  /// `void Function()`, so any async close would have its Future
  /// silently dropped. Idempotent.
  void close();
}

/// `package:http` backed transport. Default for production builds.
///
/// All requests have a hard [timeout] (default 30s) so a hung endpoint
/// can never freeze the UI; callers can (and should) also cancel via
/// their own timeout. The underlying [http.Client] is closed via
/// [close] so frequent LLM client rebuilds don't leak socket pools.
class HttpLlmTransport implements LlmTransport {
  final http.Client _client;
  final Duration timeout;
  HttpLlmTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  @override
  Future<String> postJson({
    required String url,
    required Map<String, String> headers,
    required String body,
  }) async {
    final response = await _client
        .post(
          Uri.parse(url),
          headers: headers,
          body: body,
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  @override
  void close() => _client.close();
}

/// LLM client. Send a [LlmChatRequest], get a [LlmChatResponse] back.
///
/// Auto-detects Anthropic vs OpenAI message format based on the base
/// URL when [LlmConfig.format] is left unspecified.
///
/// Call [close] when discarding a client instance to release the
/// underlying HTTP connection pool. The Riverpod provider wires this
/// up via `ref.onDispose`.
class LlmClient {
  final LlmConfig config;
  final LlmTransport transport;

  LlmClient({required this.config, LlmTransport? transport})
      : transport = transport ?? HttpLlmTransport();

  /// Release any held resources (HTTP connection pool etc.). Safe to
  /// call multiple times; implementations must be idempotent. Synchronous
  /// so callers in dispose / onDispose callbacks (which take `void Function()`)
  /// can invoke it without fire-and-forget concerns.
  void close() => transport.close();

  /// Sends a chat completion request and returns the assistant text.
  /// Throws [LlmException] on any non-2xx response or malformed JSON.
  /// Auto-detects Anthropic vs OpenAI format based on the base URL.
  Future<LlmChatResponse> chat(LlmChatRequest request) async {
    if (!config.isConfigured) {
      throw LlmException(
        'LLM not configured — please set baseUrl, apiKey, and model',
      );
    }
    if (!config.hasSafeEndpoint) {
      throw LlmException(
        'Remote LLM endpoints must use HTTPS; HTTP is allowed only on localhost',
      );
    }
    if (_isAnthropic(config.baseUrl)) {
      return _chatAnthropic(request);
    }
    return _chatOpenAi(request);
  }

  /// True when the base URL clearly points at an Anthropic-compatible
  /// endpoint. The heuristics are conservative to avoid mis-formatting
  /// requests against a proxy that happens to contain the substring
  /// "anthropic" in a path fragment.
  bool _isAnthropic(String baseUrl) {
    final u = baseUrl.toLowerCase().trim();
    if (u.isEmpty) return false;
    // Explicit known hosts.
    if (u.contains('api.anthropic.com')) return true;
    if (u.contains('api.minimaxi.com')) return true;
    // Path ending in /anthropic or /anthropic/ — user has literally
    // opted in to the format by setting the endpoint suffix.
    if (u.endsWith('/anthropic')) return true;
    if (u.endsWith('/anthropic/')) return true;
    return false;
  }

  // ── OpenAI-compatible format ──────────────────────────────────────
  Future<LlmChatResponse> _chatOpenAi(LlmChatRequest request) async {
    final url = _chatCompletionsUrl(config.baseUrl);
    final model = request.model.isEmpty ? config.model : request.model;
    final body = jsonEncode({
      ...request.toJson(),
      'model': model,
      ..._providerOptions(model),
    });
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };
    final raw =
        await transport.postJson(url: url, headers: headers, body: body);
    final dynamic decoded = _decodeJsonObject(raw);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmException('No choices in response: $raw');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw LlmException('Unexpected choice type in response: $raw');
    }
    final message = first['message'];
    final content = _visibleContent(message);
    final usage = decoded['usage'];
    int? _readInt(dynamic n) {
      if (n is num) return n.toInt();
      if (n is String) return int.tryParse(n);
      return null;
    }

    String? reason;
    if (first['finish_reason'] is String)
      reason = first['finish_reason'] as String;
    return LlmChatResponse(
      content: content,
      promptTokens: usage is Map<String, dynamic>
          ? _readInt(usage['prompt_tokens'])
          : null,
      completionTokens: usage is Map<String, dynamic>
          ? _readInt(usage['completion_tokens'])
          : null,
      finishReason: reason,
    );
  }

  // ── Anthropic-compatible format (MiniMax /anthropic) ──────────────
  Future<LlmChatResponse> _chatAnthropic(LlmChatRequest request) async {
    var base = _normalizeBaseUrl(config.baseUrl);
    final url = '$base/v1/messages';
    final model = request.model.isEmpty ? config.model : request.model;
    String? system;
    final msgs = <Map<String, dynamic>>[];
    for (final m in request.messages) {
      if (m.role == 'system') {
        system = m.content;
      } else {
        msgs.add({'role': m.role, 'content': m.content});
      }
    }
    final body = jsonEncode({
      'model': model,
      'max_tokens': request.maxTokens ?? 1024,
      'temperature': request.temperature,
      'messages': msgs,
      if (system != null) 'system': system,
      'stream': false,
      ..._providerOptions(model),
    });
    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
    };
    final raw =
        await transport.postJson(url: url, headers: headers, body: body);
    final dynamic decoded = _decodeJsonObject(raw);
    // Anthropic response: content is a list of blocks [{type:"text",text:"..."}]
    final contentList = decoded['content'];
    if (contentList is! List || contentList.isEmpty) {
      // Some providers return a non-empty message even with no text
      // blocks (e.g. a tool_use). Surface a clear error instead of the
      // empty string we'd get from joining zero blocks.
      final err = decoded['error'];
      if (err is Map && err['message'] is String) {
        throw LlmException('Upstream error: ${err['message']}');
      }
      throw LlmException('No content in response: $raw');
    }
    final textParts = <String>[];
    for (final block in contentList) {
      if (block is Map<String, dynamic>) {
        if (block['type'] == 'text' && block['text'] is String) {
          textParts.add(block['text'] as String);
        } else if (block['type'] == 'thinking' && block['thinking'] is String) {
          // Ignore: reasoning blocks aren't user-facing.
        } else if (block['type'] == 'tool_use') {
          // Surface a hint instead of silently dropping it.
          textParts.add('[tool_use: ${block['name']}]');
        }
      }
    }
    if (textParts.isEmpty) {
      throw LlmException(
          'Model returned non-text content only — try a different model');
    }
    int? _readInt(dynamic n) {
      if (n is num) return n.toInt();
      if (n is String) return int.tryParse(n);
      return null;
    }

    final usage = decoded['usage'];
    String? reason;
    if (decoded['stop_reason'] is String)
      reason = decoded['stop_reason'] as String;
    return LlmChatResponse(
      content: textParts.join().trim(),
      promptTokens: usage is Map<String, dynamic>
          ? _readInt(usage['input_tokens'])
          : null,
      completionTokens: usage is Map<String, dynamic>
          ? _readInt(usage['output_tokens'])
          : null,
      finishReason: reason,
    );
  }

  /// Build the chat-completions URL. The user-supplied base URL can
  /// be either:
  ///   - https://api.openai.com/v1            → /chat/completions
  ///   - https://api.openai.com/v1/           → /chat/completions
  ///   - http://localhost:11434/v1            → /chat/completions
  ///   - https://open.bigmodel.cn/api/paas/v4 → /chat/completions (no /v1)
  ///   - https://example.com                  → /v1/chat/completions
  static String _chatCompletionsUrl(String baseUrl) {
    var b = _normalizeBaseUrl(baseUrl);
    if (b.toLowerCase().endsWith('/chat/completions')) return b;
    // If URL already ends with a /vN style path segment (v1, v2, v4,
    // v1beta, v2-preview etc.) don't append /v1.
    if (!RegExp(r'/v\d+[a-zA-Z0-9_-]*$').hasMatch(b)) b = '$b/v1';
    return '$b/chat/completions';
  }

  static Map<String, dynamic> _providerOptions(String model) {
    if (model.trim().toLowerCase() != 'minimax-m3') return const {};
    return const {
      'thinking': {'type': 'disabled'},
    };
  }

  /// Shared decoder gate: parse JSON, enforce the top-level shape,
  /// throw a typed [LlmException] on any failure so callers only have
  /// to catch one exception class.
  static Map<String, dynamic> _decodeJsonObject(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw LlmException('Malformed JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw LlmException(
          'Unexpected response shape (expected JSON object): $raw');
    }
    return decoded;
  }

  static String _visibleContent(dynamic message) {
    if (message is! Map<String, dynamic>) return '';
    final raw = message['content'];
    if (raw is! String) return '';
    return raw
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .trim();
  }

  static String _normalizeBaseUrl(String baseUrl) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }
}
