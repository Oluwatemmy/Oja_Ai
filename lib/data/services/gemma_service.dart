import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

/// Thin wrapper around flutter_gemma. Every touchpoint with the plugin API
/// lives here so the rest of the app only sees Dart primitives.
class GemmaService {
  /// Gemma 4 E4B `.litertlm` — 4.3 GB on disk, ~5.5 GB resident with the
  /// USM audio encoder + vision + KV cache. Best on-device Gemma for
  /// hearing-and-reasoning, fits any phone with 8 GB+ RAM.
  ///
  /// Local mode uses this as the ONE model doing everything: audio in,
  /// reasoning, function calling, structured output, and vision for Snap.
  ///
  /// Gated repo — build must include an HF token that has accepted the
  /// Gemma license:
  ///   `flutter build apk --debug --dart-define=HUGGINGFACE_TOKEN=hf_xxx`
  ///
  /// To trade down to E2B (2.4 GB, phones with 6 GB RAM):
  ///   `--dart-define=OJA_MODEL_URL=https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`
  static const String modelUrl = String.fromEnvironment(
    'OJA_MODEL_URL',
    defaultValue:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
  );

  /// `gemma4` (default, native tool-call tokens + vision + audio).
  static const String modelTypeName = String.fromEnvironment(
    'OJA_MODEL_TYPE',
    defaultValue: 'gemma4',
  );

  static ModelType get _modelType => switch (modelTypeName) {
        'gemma4' => ModelType.gemma4,
        'qwen3' => ModelType.qwen3,
        _ => ModelType.gemmaIt,
      };

  /// Only Gemma 4 (E2B/E4B/12B) has the vision + audio encoders.
  static bool get supportsMultimodal => _modelType == ModelType.gemma4;

  static const String huggingFaceToken =
      String.fromEnvironment('HUGGINGFACE_TOKEN');

  /// Context window. Must be ≥1024 (litertlm floor). 2048 is plenty for a
  /// transcribed voice note + tool round-trips + name-biasing prompt.
  static const int maxTokens = int.fromEnvironment(
    'OJA_MAX_TOKENS',
    defaultValue: 2048,
  );

  InferenceModel? _model;

  bool get isLoaded => _model != null;

  /// Registers the LiteRT-LM engine. Call once at app start.
  Future<void> initialize() async {
    await FlutterGemma.initialize(
      inferenceEngines: [LiteRtLmEngine()],
      huggingFaceToken: huggingFaceToken.isEmpty ? null : huggingFaceToken,
    );
  }

  /// Loads the installed model into memory.
  /// Returns false when no model is installed yet (first launch).
  Future<bool> tryLoadModel() async {
    if (_model != null) return true;
    if (!FlutterGemma.hasActiveModel()) return false;
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      supportImage: supportsMultimodal,
      // Audio ON: local mode is Gemma-listens-to-audio-natively. When only
      // running the online mode the setup screen skips loading Gemma at
      // all, so this only takes effect on the local path.
      supportAudio: supportsMultimodal,
      // Explicit GPU pick — Adreno/Mali via OpenCL is faster; engine falls
      // back to CPU automatically when OpenCL isn't available.
      preferredBackend: PreferredBackend.gpu,
    );
    return true;
  }

  /// Downloads the model, emitting progress 0..100.
  Stream<int> installModel() {
    final controller = StreamController<int>();
    () async {
      try {
        await FlutterGemma.installModel(
          modelType: _modelType,
          fileType: ModelFileType.litertlm,
        )
            .fromNetwork(
              modelUrl,
              token: huggingFaceToken.isEmpty ? null : huggingFaceToken,
              // Real foreground service + notification: without this Android
              // kills the download as soon as the app is backgrounded.
              foreground: true,
            )
            .withProgress(controller.add)
            .install();
        controller.add(100);
        await controller.close();
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  /// Fresh chat per agent run keeps the context window from growing across
  /// unrelated recordings — matters for both memory and prompt hygiene.
  Future<InferenceChat> createChat({
    required List<Tool> tools,
    String? systemInstruction,
    double temperature = 0.2,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxOutputTokens,
  }) async {
    final model = _model;
    if (model == null) {
      throw StateError('Model not loaded. Call tryLoadModel() first.');
    }
    return model.createChat(
      temperature: temperature,
      tools: tools,
      supportsFunctionCalls: true,
      modelType: _modelType,
      supportImage: supportsMultimodal,
      supportAudio: supportsMultimodal,
      systemInstruction: systemInstruction,
      toolChoice: toolChoice,
      maxOutputTokens: maxOutputTokens,
    );
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
  }
}
