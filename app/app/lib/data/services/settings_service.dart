import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/app_settings.dart';

/// Persisted settings backed by the platform keystore. API key stays out
/// of shared_preferences and out of the debugger.
class SettingsService extends ChangeNotifier {
  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kMode = 'oja.mode';
  static const _kApiKey = 'oja.openrouter.key';
  static const _kModel = 'oja.openrouter.model';
  static const _kGroqKey = 'oja.groq.key';

  /// Compile-time default from --dart-define=GROQ_API_KEY / OPENROUTER_KEY,
  /// used as the initial value if secure storage doesn't yet hold one.
  /// Lets the demo APK ship with keys baked in without leaking them to
  /// public storage.
  static const String _defaultGroqKey =
      String.fromEnvironment('GROQ_API_KEY');
  static const String _defaultOpenRouterKey =
      String.fromEnvironment('OPENROUTER_KEY');

  AppSettings _current = AppSettings.initial;
  AppSettings get current => _current;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final mode = await _storage.read(key: _kMode);
    final key = await _storage.read(key: _kApiKey);
    final model = await _storage.read(key: _kModel);
    final groqKey = await _storage.read(key: _kGroqKey);

    // Bootstrap compile-time defaults into secure storage on first launch
    // so a demo build with baked-in keys stops re-baking on every run.
    final resolvedOpenRouterKey = (key != null && key.isNotEmpty)
        ? key
        : _defaultOpenRouterKey;
    final resolvedGroqKey = (groqKey != null && groqKey.isNotEmpty)
        ? groqKey
        : _defaultGroqKey;
    if ((key == null || key.isEmpty) && resolvedOpenRouterKey.isNotEmpty) {
      await _storage.write(key: _kApiKey, value: resolvedOpenRouterKey);
    }
    if ((groqKey == null || groqKey.isEmpty) && resolvedGroqKey.isNotEmpty) {
      await _storage.write(key: _kGroqKey, value: resolvedGroqKey);
    }

    _current = AppSettings(
      mode: mode == 'online' ? AppMode.online : AppMode.local,
      openRouterApiKey: resolvedOpenRouterKey,
      groqApiKey: resolvedGroqKey,
      openRouterModel: model ?? AppSettings.defaultOnlineModel,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(AppMode mode) async {
    if (_current.mode == mode) return;
    _current = _current.copyWith(mode: mode);
    await _storage.write(
      key: _kMode,
      value: mode == AppMode.online ? 'online' : 'local',
    );
    notifyListeners();
  }

  Future<void> setApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    _current = _current.copyWith(openRouterApiKey: trimmed);
    await _storage.write(key: _kApiKey, value: trimmed);
    notifyListeners();
  }

  Future<void> setGroqApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    _current = _current.copyWith(groqApiKey: trimmed);
    await _storage.write(key: _kGroqKey, value: trimmed);
    notifyListeners();
  }

  Future<void> setOnlineModel(String model) async {
    _current = _current.copyWith(openRouterModel: model);
    await _storage.write(key: _kModel, value: model);
    notifyListeners();
  }

  Future<void> clearApiKey() => setApiKey('');
}
