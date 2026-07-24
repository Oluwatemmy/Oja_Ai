import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Cloud transcription via Groq's Whisper endpoint. Runs
/// whisper-large-v3-turbo on Groq's LPU chips — near-SOTA accuracy at
/// ~0.5–1s per short clip (vs 5–8s for on-device Whisper small on CPU).
///
/// Same shape as [WhisperService.transcribe] so the agent path can swap
/// them without knowing which one it's calling.
class GroqTranscriberService {
  GroqTranscriberService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const String _model = 'whisper-large-v3-turbo';

  static const String _pidginBias =
      'Nigerian market trader recording sales and debts in naira. '
      'Common titles used in names: Mama, Mummy, Papa, Iya, Baba, Madam, '
      'Oga, Bros, Sister, Aunty, Alhaji, Alhaja, Chief. '
      'Pidgin phrases to expect verbatim: "she don pay am", "he don pay", '
      '"e don pay", "she never pay", "he never pay", "e no pay", '
      '"dem owe me", "e dey owe me", "I sell am", "she buy am", '
      '"carry am go", "abeg", "wetin", "how much".';

  final http.Client _client;

  /// Transcribes one or more 16 kHz mono PCM16 WAV chunks. Empty list or
  /// missing API key returns an empty string.
  Future<String> transcribe(
    List<Uint8List> wavChunks, {
    required String apiKey,
  }) async {
    if (wavChunks.isEmpty || apiKey.trim().isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < wavChunks.length; i++) {
      final text = await _transcribeOne(wavChunks[i], apiKey);
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  Future<String> _transcribeOne(Uint8List wavBytes, String apiKey) async {
    return _withRetry(() async {
      final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..fields['model'] = _model
        ..fields['response_format'] = 'json'
        ..fields['language'] = 'en'
        ..fields['prompt'] = _pidginBias
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: 'audio.wav',
        ));
      final streamed =
          await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) {
        throw GroqException(
          'Groq returned ${response.statusCode}: ${_extractError(response.body)}',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['text'] == null) return '';
      return (decoded['text'] as String).trim();
    });
  }

  static Future<T> _withRetry<T>(
    Future<T> Function() body, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await body();
      } on GroqException catch (e) {
        final code = e.statusCode ?? 0;
        if (code >= 400 && code < 500 && code != 429) rethrow;
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << attempt)));
      }
    }
    if (lastError is Exception) throw lastError;
    throw GroqException('Groq unreachable after $maxAttempts attempts');
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

class GroqException implements Exception {
  const GroqException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isAuth => statusCode == 401 || statusCode == 403;
  bool get isRateLimit => statusCode == 429;

  @override
  String toString() => message;
}
