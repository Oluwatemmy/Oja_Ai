import 'package:flutter/foundation.dart';

import '../../../../data/services/gemma_service.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../data/services/settings_service.dart';
import '../../../../domain/models/app_settings.dart';

enum SetupPhase {
  loading,
  pickMode,          // First launch: local vs online
  enterApiKeys,      // Online mode: needs both OpenRouter + Groq keys
  needsDownload,     // Local mode: ready to download Gemma
  downloadingGemma,
  loadingModel,
  ready,
  error,
}

class SetupViewModel extends ChangeNotifier {
  SetupViewModel({
    required GemmaService gemma,
    required SettingsService settings,
    required OpenRouterService openRouter,
  })  : _gemma = gemma,
        _settings = settings,
        _openRouter = openRouter;

  final GemmaService _gemma;
  final SettingsService _settings;
  final OpenRouterService _openRouter;

  SetupPhase _phase = SetupPhase.loading;
  SetupPhase get phase => _phase;

  int _progress = 0;
  int get progress => _progress;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  String _apiKeyInput = '';
  String get apiKeyInput => _apiKeyInput;
  set apiKeyInput(String v) {
    _apiKeyInput = v;
    notifyListeners();
  }

  String _groqKeyInput = '';
  String get groqKeyInput => _groqKeyInput;
  set groqKeyInput(String v) {
    _groqKeyInput = v;
    notifyListeners();
  }

  bool _testingKey = false;
  bool get testingKey => _testingKey;

  AppSettings get settings => _settings.current;

  bool get isDownloading => _phase == SetupPhase.downloadingGemma;

  String get progressLabel {
    switch (_phase) {
      case SetupPhase.downloadingGemma:
        return 'Downloading Gemma — $_progress%';
      case SetupPhase.loadingModel:
        return 'E dey arrange di brain…';
      default:
        return '';
    }
  }

  Future<void> start() async {
    _setPhase(SetupPhase.loading);
    try {
      await _settings.load();
      await _gemma.initialize();

      // First launch: no keys, no downloaded model → show mode picker.
      final first = _settings.current.openRouterApiKey.isEmpty &&
          _settings.current.groqApiKey.isEmpty &&
          _settings.current.mode == AppMode.local &&
          !await _localAssetsReady();
      if (first) {
        _setPhase(SetupPhase.pickMode);
        return;
      }
      await _routeToNextStep();
    } catch (e) {
      _fail('E no fit start: $e');
    }
  }

  /// Re-runs the mode-vs-assets check without re-reading storage. Used
  /// when mode changes in Settings — if the new mode needs setup we drop
  /// back to the setup screen; otherwise we stay on Home.
  Future<void> recheckAssets() async {
    _setPhase(SetupPhase.loading);
    try {
      await _routeToNextStep();
    } catch (e) {
      _fail(_friendly(e));
    }
  }

  /// Flip to the other mode from the setup screen.
  Future<void> switchToOtherMode() async {
    final other = _settings.current.mode == AppMode.local
        ? AppMode.online
        : AppMode.local;
    await _settings.setMode(other);
    await _routeToNextStep();
  }

  Future<bool> _localAssetsReady() async {
    try {
      return await _gemma.tryLoadModel();
    } catch (_) {
      return false;
    }
  }

  Future<void> pickLocal() async {
    await _settings.setMode(AppMode.local);
    await _routeToNextStep();
  }

  Future<void> pickOnline() async {
    await _settings.setMode(AppMode.online);
    await _routeToNextStep();
  }

  Future<void> submitApiKeys() async {
    final openRouterKey = _apiKeyInput.trim().isNotEmpty
        ? _apiKeyInput.trim()
        : _settings.current.openRouterApiKey;
    final groqKey = _groqKeyInput.trim().isNotEmpty
        ? _groqKeyInput.trim()
        : _settings.current.groqApiKey;

    if (openRouterKey.isEmpty) {
      _errorMessage = 'Paste your OpenRouter key first.';
      notifyListeners();
      return;
    }
    if (groqKey.isEmpty) {
      _errorMessage = 'Paste your Groq key first (needed for voice → text).';
      notifyListeners();
      return;
    }

    _testingKey = true;
    _errorMessage = '';
    notifyListeners();
    final ok = await _openRouter.testConnection(
      apiKey: openRouterKey,
      model: _settings.current.openRouterModel,
    );
    _testingKey = false;
    if (!ok) {
      _errorMessage = 'OpenRouter key no work. Check am and try again.';
      notifyListeners();
      return;
    }

    await _settings.setApiKey(openRouterKey);
    await _settings.setGroqApiKey(groqKey);
    _apiKeyInput = '';
    _groqKeyInput = '';
    await _routeToNextStep();
  }

  Future<void> _routeToNextStep() async {
    final mode = _settings.current.mode;
    if (mode == AppMode.local) {
      final loaded = await _localAssetsReady();
      _setPhase(loaded ? SetupPhase.ready : SetupPhase.needsDownload);
    } else {
      // Online mode requires both keys.
      final hasBoth = _settings.current.openRouterApiKey.isNotEmpty &&
          _settings.current.groqApiKey.isNotEmpty;
      _setPhase(hasBoth ? SetupPhase.ready : SetupPhase.enterApiKeys);
    }
  }

  Future<void> download() async {
    final mode = _settings.current.mode;
    if (mode == AppMode.online) {
      _setPhase(SetupPhase.ready);
      return;
    }
    _progress = 0;
    _setPhase(SetupPhase.downloadingGemma);
    try {
      await for (final progress in _gemma.installModel()) {
        if (progress > _progress) {
          _progress = progress;
          notifyListeners();
        }
      }
    } catch (e) {
      _fail(_friendly(e));
      return;
    }
    _setPhase(SetupPhase.loadingModel);
    try {
      final loaded = await _gemma.tryLoadModel();
      if (loaded) {
        _setPhase(SetupPhase.ready);
      } else {
        _fail('Model download finish but no fit load. Try restart di app.');
      }
    } catch (e) {
      _fail(_friendly(e));
    }
  }

  void _setPhase(SetupPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _setPhase(SetupPhase.error);
  }

  static String _friendly(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('oom') ||
        text.contains('memory') ||
        text.contains('alloc')) {
      return 'Your phone RAM no reach. Gemma 4 E4B need 8 GB+.';
    }
    return 'Something no work: $error';
  }
}
