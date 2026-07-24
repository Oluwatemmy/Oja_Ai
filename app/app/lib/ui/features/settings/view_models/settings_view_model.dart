import 'package:flutter/foundation.dart';

import '../../../../data/services/openrouter_service.dart';
import '../../../../data/services/settings_service.dart';
import '../../../../domain/models/app_settings.dart';
import '../../setup/view_models/setup_view_model.dart';

enum ConnectionTest { idle, running, success, failure }

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required SettingsService settings,
    required OpenRouterService openRouter,
    required SetupViewModel setup,
  })  : _settings = settings,
        _openRouter = openRouter,
        _setup = setup {
    _settings.addListener(notifyListeners);
    _apiKeyDraft = _settings.current.openRouterApiKey;
  }

  final SettingsService _settings;
  final OpenRouterService _openRouter;
  final SetupViewModel _setup;

  AppSettings get current => _settings.current;

  String _apiKeyDraft = '';
  String get apiKeyDraft => _apiKeyDraft;
  set apiKeyDraft(String v) {
    _apiKeyDraft = v;
    notifyListeners();
  }

  String _groqKeyDraft = '';
  String get groqKeyDraft => _groqKeyDraft;
  set groqKeyDraft(String v) {
    _groqKeyDraft = v;
    notifyListeners();
  }

  ConnectionTest _testState = ConnectionTest.idle;
  ConnectionTest get testState => _testState;

  String _testMessage = '';
  String get testMessage => _testMessage;

  /// Switch mode AND make sure the new mode's assets are ready. Returns
  /// true if the app is ready to use in the new mode immediately; false
  /// if a download / setup step is now needed (the setup screen will
  /// appear automatically because SetupViewModel.phase drops out of
  /// `ready` — the caller should pop back to the root).
  Future<bool> setMode(AppMode mode) async {
    if (_settings.current.mode == mode) return true;
    await _settings.setMode(mode);
    await _setup.recheckAssets();
    return _setup.phase == SetupPhase.ready;
  }

  Future<void> saveApiKey() async {
    await _settings.setApiKey(_apiKeyDraft.trim());
  }

  Future<void> saveGroqKey() async {
    await _settings.setGroqApiKey(_groqKeyDraft.trim());
  }

  Future<void> testConnection() async {
    _testState = ConnectionTest.running;
    _testMessage = '';
    notifyListeners();
    final settings = _settings.current;
    final key = _apiKeyDraft.trim().isNotEmpty
        ? _apiKeyDraft.trim()
        : settings.openRouterApiKey;
    if (key.isEmpty) {
      _testState = ConnectionTest.failure;
      _testMessage = 'No API key set.';
      notifyListeners();
      return;
    }
    final ok = await _openRouter.testConnection(
      apiKey: key,
      model: settings.openRouterModel,
    );
    _testState = ok ? ConnectionTest.success : ConnectionTest.failure;
    _testMessage = ok ? 'Connection OK.' : 'Test failed. Check your key.';
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(notifyListeners);
    super.dispose();
  }
}
