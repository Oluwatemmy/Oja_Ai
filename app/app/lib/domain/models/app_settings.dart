/// Where OjaAI runs its reasoning.
enum AppMode {
  /// Fully on-device: Gemma 4 E4B (audio + vision + reasoning). No network.
  local,

  /// Whisper transcribes locally, Gemma 4 31B on OpenRouter reasons.
  /// Better raw model, needs data + an API key.
  online,
}

/// Persisted app configuration. Kept small — the credential is stored in
/// the platform keystore (Android EncryptedSharedPreferences / iOS Keychain).
class AppSettings {
  const AppSettings({
    required this.mode,
    required this.openRouterApiKey,
    required this.groqApiKey,
    this.openRouterModel = defaultOnlineModel,
  });

  final AppMode mode;
  final String openRouterApiKey;

  /// Optional. When set, online mode uses Groq's whisper-large-v3-turbo
  /// instead of the ~5–8 s on-device Whisper small. Sub-second cloud ASR.
  final String groqApiKey;
  final String openRouterModel;

  static const defaultOnlineModel = 'google/gemma-4-31b-it';
  static const AppSettings initial = AppSettings(
    mode: AppMode.local,
    openRouterApiKey: '',
    groqApiKey: '',
  );

  bool get isOnlineReady =>
      mode == AppMode.online && openRouterApiKey.isNotEmpty;

  bool get usesCloudTranscription =>
      mode == AppMode.online && groqApiKey.isNotEmpty;

  AppSettings copyWith({
    AppMode? mode,
    String? openRouterApiKey,
    String? groqApiKey,
    String? openRouterModel,
  }) =>
      AppSettings(
        mode: mode ?? this.mode,
        openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
        groqApiKey: groqApiKey ?? this.groqApiKey,
        openRouterModel: openRouterModel ?? this.openRouterModel,
      );
}
