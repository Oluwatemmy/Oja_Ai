import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../../../data/repositories/agent_repository.dart';
import '../../../../data/repositories/ledger_repository.dart';
import '../../../core/widgets/confirm_models.dart';

enum SnapPhase { initializing, ready, thinking, confirm, error }

class SnapViewModel extends ChangeNotifier {
  SnapViewModel({
    required AgentRepository agent,
    required LedgerRepository ledger,
  })  : _agent = agent,
        _ledger = ledger;

  final AgentRepository _agent;
  final LedgerRepository _ledger;

  CameraController? _controller;
  CameraController? get controller => _controller;

  SnapPhase _phase = SnapPhase.initializing;
  SnapPhase get phase => _phase;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  List<ConfirmItem> _queue = [];
  int _queueIndex = 0;

  ConfirmItem? get currentConfirm =>
      _phase == SnapPhase.confirm && _queueIndex < _queue.length
          ? _queue[_queueIndex]
          : null;

  int get confirmNumber => _queueIndex + 1;
  int get confirmCount => _queue.length;

  /// Set true when the whole snap batch has been confirmed —
  /// the view navigates to the Ledger tab.
  bool _finished = false;
  bool get finished => _finished;

  Future<void> initCamera() async {
    _finished = false;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No camera dey dis phone.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      _controller = controller;
      _setPhase(SnapPhase.ready);
    } catch (e) {
      _fail('Camera no gree open: $e');
    }
  }

  Future<void> shutter() async {
    final controller = _controller;
    if (controller == null || _phase != SnapPhase.ready) return;
    _setPhase(SnapPhase.thinking);
    try {
      final file = await controller.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      final result = await _agent.runSnapEntry(bytes);
      _queue = confirmQueueFrom(result);
      _queueIndex = 0;
      if (_queue.isEmpty) {
        _fail(result.answer.isEmpty
            ? 'I no fit read anything for di page. Snap am again.'
            : result.answer);
      } else {
        _setPhase(SnapPhase.confirm);
      }
    } catch (e) {
      _fail('Snap no work: $e');
    }
  }

  int _committedCount = 0;

  Future<void> confirmYes() async {
    final item = currentConfirm;
    if (item == null) return;
    if (item.isPayment) {
      await _ledger.commitPayment(item.payment!);
    } else {
      await _ledger.commitEntry(item.entry!);
    }
    _committedCount++;
    _queueIndex++;
    _finishQueueIfDone();
  }

  /// Drop only the current record and continue with the rest.
  void confirmSkip() {
    if (currentConfirm == null) return;
    _queueIndex++;
    _finishQueueIfDone();
  }

  void _finishQueueIfDone() {
    if (_queueIndex < _queue.length) {
      notifyListeners();
      return;
    }
    final committedAny = _committedCount > 0;
    _queue = [];
    _queueIndex = 0;
    _committedCount = 0;
    if (committedAny) {
      _finished = true;
      notifyListeners();
    } else {
      // Everything skipped — back to the camera.
      _setPhase(SnapPhase.ready);
    }
  }

  void confirmNo() {
    _queue = [];
    _queueIndex = 0;
    _committedCount = 0;
    _setPhase(SnapPhase.ready);
  }

  void retryAfterError() {
    if (_controller == null) {
      initCamera();
    } else {
      _setPhase(SnapPhase.ready);
    }
  }

  void _setPhase(SnapPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _setPhase(SnapPhase.error);
  }

  Future<void> disposeCamera() async {
    await _controller?.dispose();
    _controller = null;
    _phase = SnapPhase.initializing;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
