import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.setLanguage('en-NG');
    } catch (_) {
      // Nigerian English voice not installed; OS default is fine.
    }
    await _tts.setSpeechRate(0.5);
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureInitialized();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
