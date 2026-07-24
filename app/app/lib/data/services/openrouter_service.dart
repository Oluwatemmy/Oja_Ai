import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Minimal OpenAI-compatible client for OpenRouter.
///
/// OpenRouter's chat.completions endpoint routes to underlying providers.
/// For Gemma 4 31B (`google/gemma-4-31b-it`) the provider is Google Vertex —
/// the tools schema is passed through, and the response contains real
/// `tool_calls`. We match the shape exactly so the agent loop can look
/// the same as the on-device Gemma path.
class OpenRouterService {
  OpenRouterService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _endpoint =
      'https://openrouter.ai/api/v1/chat/completions';

  final http.Client _client;

  Future<OpenRouterResponse> chat({
    required String apiKey,
    required String model,
    required List<OpenRouterMessage> messages,
    List<Map<String, dynamic>> tools = const [],
    String toolChoice = 'auto',
    double temperature = 0.2,
    int maxTokens = 512,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': [for (final m in messages) m.toJson()],
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = toolChoice;
    }
    final encoded = jsonEncode(body);
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      // Nice-to-have per OpenRouter's guidelines.
      'HTTP-Referer': 'https://ojaai.app',
      'X-Title': 'OjaAI',
    };
    return _withRetry(() async {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: headers,
            body: encoded,
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 400) {
        throw OpenRouterException(
          'OpenRouter returned ${response.statusCode}: '
          '${_extractError(response.body)}',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return OpenRouterResponse.fromJson(decoded);
    });
  }

  /// Retries on transient network / 5xx / 429 errors, with exponential
  /// backoff. Permanent errors (401/403/400) bubble immediately.
  static Future<T> _withRetry<T>(
    Future<T> Function() body, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await body();
      } on OpenRouterException catch (e) {
        // Permanent errors (auth, bad request) don't retry.
        final code = e.statusCode ?? 0;
        if (code >= 400 && code < 500 && code != 429) rethrow;
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        // "Connection reset by peer", "Connection closed before response",
        // "Broken pipe" — the classic transient shapes.
        lastError = e;
      }
      if (attempt < maxAttempts - 1) {
        final backoffMs = 400 * (1 << attempt); // 400ms, 800ms
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }
    if (lastError is Exception) throw lastError;
    throw OpenRouterException(
      'OpenRouter unreachable after $maxAttempts attempts',
    );
  }

  /// Cheap round-trip to validate the API key and model access.
  Future<bool> testConnection({
    required String apiKey,
    required String model,
  }) async {
    try {
      await chat(
        apiKey: apiKey,
        model: model,
        messages: [
          OpenRouterMessage.user('ping'),
        ],
        temperature: 0,
        maxTokens: 8,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _extractError(String body) {
    try {
      final map = jsonDecode(body);
      if (map is Map && map['error'] is Map) {
        return (map['error']['message'] ?? body).toString();
      }
      return body;
    } catch (_) {
      return body;
    }
  }

  void dispose() => _client.close();
}

class OpenRouterMessage {
  const OpenRouterMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
    this.imageBase64,
  });

  final String role;
  final String? content;
  final List<OpenRouterToolCall>? toolCalls;
  final String? toolCallId;
  final String? name;

  /// Base64-encoded JPEG for vision inputs (Gemma 4 31B accepts images).
  final String? imageBase64;

  factory OpenRouterMessage.system(String content) =>
      OpenRouterMessage(role: 'system', content: content);

  factory OpenRouterMessage.user(String content) =>
      OpenRouterMessage(role: 'user', content: content);

  factory OpenRouterMessage.userWithImage({
    required String text,
    required String imageBase64,
  }) =>
      OpenRouterMessage(
        role: 'user',
        content: text,
        imageBase64: imageBase64,
      );

  factory OpenRouterMessage.assistantToolCalls(
          List<OpenRouterToolCall> calls) =>
      OpenRouterMessage(role: 'assistant', toolCalls: calls);

  factory OpenRouterMessage.tool({
    required String toolCallId,
    required String name,
    required String content,
  }) =>
      OpenRouterMessage(
        role: 'tool',
        toolCallId: toolCallId,
        name: name,
        content: content,
      );

  Map<String, dynamic> toJson() {
    final img = imageBase64;
    if (img != null) {
      // OpenAI-style multimodal content array.
      return {
        'role': role,
        'content': [
          {'type': 'text', 'text': content ?? ''},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$img'},
          },
        ],
      };
    }
    return {
      'role': role,
      if (content != null) 'content': content,
      if (toolCalls != null && toolCalls!.isNotEmpty)
        'tool_calls': [for (final t in toolCalls!) t.toJson()],
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (name != null) 'name': name,
    };
  }
}

class OpenRouterToolCall {
  const OpenRouterToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  factory OpenRouterToolCall.fromJson(Map<String, dynamic> json) {
    final fn = (json['function'] as Map<String, dynamic>? ?? const {});
    final rawArgs = fn['arguments'];
    final args = rawArgs is String
        ? (rawArgs.trim().isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(rawArgs) as Map<String, dynamic>)
        : rawArgs is Map
            ? Map<String, dynamic>.from(rawArgs)
            : const <String, dynamic>{};
    return OpenRouterToolCall(
      id: (json['id'] ?? '').toString(),
      name: (fn['name'] ?? '').toString(),
      arguments: args,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': jsonEncode(arguments),
        },
      };
}

class OpenRouterResponse {
  const OpenRouterResponse({
    required this.text,
    required this.toolCalls,
    required this.finishReason,
  });

  final String text;
  final List<OpenRouterToolCall> toolCalls;
  final String finishReason;

  bool get hasToolCalls => toolCalls.isNotEmpty;

  factory OpenRouterResponse.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      return const OpenRouterResponse(
          text: '', toolCalls: [], finishReason: 'no_choice');
    }
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>? ?? const {};
    final rawText = message['content'];
    final text = rawText is String
        ? rawText
        : rawText is List
            ? rawText
                .whereType<Map>()
                .map((part) => (part['text'] ?? '').toString())
                .join()
            : '';
    final toolCalls = (message['tool_calls'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(OpenRouterToolCall.fromJson)
        .toList();
    return OpenRouterResponse(
      text: text,
      toolCalls: toolCalls,
      finishReason: (choice['finish_reason'] ?? '').toString(),
    );
  }
}

class OpenRouterException implements Exception {
  const OpenRouterException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isAuth => statusCode == 401 || statusCode == 403;
  bool get isRateLimit => statusCode == 429;

  @override
  String toString() => message;
}
