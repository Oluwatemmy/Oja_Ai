import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/agent_repository.dart';
import '../../../../data/repositories/ledger_repository.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../../data/services/tts_service.dart';
import '../../../../domain/models/ledger_entry.dart';
import '../../../../domain/models/undoable_action.dart';
import '../../../core/widgets/confirm_models.dart';

enum HomePhase { idle, listening, thinking, confirm }

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required AgentRepository agent,
    required LedgerRepository ledger,
    required AudioRecorderService recorder,
    required TtsService tts,
  })  : _agent = agent,
        _ledger = ledger,
        _recorder = recorder,
        _tts = tts {
    _ledger.addListener(notifyListeners);
    _silenceSubscription =
        _recorder.endOfUtterance.listen((_) => stopTalk());
  }

  final AgentRepository _agent;
  final LedgerRepository _ledger;
  final AudioRecorderService _recorder;
  final TtsService _tts;
  StreamSubscription<void>? _silenceSubscription;

  HomePhase _phase = HomePhase.idle;
  HomePhase get phase => _phase;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  /// Model spoke back to the trader (usually a clarifying question).
  /// Rendered in navy, not red. Triggers the "Reply" mic button.
  String _assistantMessage = '';
  String get assistantMessage => _assistantMessage;

  bool get hasPendingReply =>
      _assistantMessage.isNotEmpty && _agent.hasPendingConversation;

  List<ConfirmItem> _queue = [];
  int _queueIndex = 0;
  int _committedCount = 0;

  bool _isContinuation = false;

  /// One-shot undo action from a voice delete/edit. Incremented [_undoNonce]
  /// tells the view it's a NEW action (so it shows a fresh snackbar even if
  /// the description is identical to a prior one).
  UndoableAction? _pendingUndo;
  UndoableAction? get pendingUndo => _pendingUndo;
  int _undoNonce = 0;
  int get undoNonce => _undoNonce;

  Future<void> performUndo() async {
    final action = _pendingUndo;
    if (action == null) return;
    _pendingUndo = null;
    notifyListeners();
    await _agent.undo(action);
  }

  void clearPendingUndo() {
    if (_pendingUndo == null) return;
    _pendingUndo = null;
    notifyListeners();
  }

  ConfirmItem? get currentConfirm =>
      _phase == HomePhase.confirm && _queueIndex < _queue.length
          ? _queue[_queueIndex]
          : null;

  int get confirmNumber => _queueIndex + 1;
  int get confirmCount => _queue.length;

  LedgerTotals get totals => _ledger.totals;
  bool get hasEntries => _ledger.entries.isNotEmpty;
  LedgerEntry? get lastEntry =>
      _ledger.entries.isEmpty ? null : _ledger.entries.first;

  Future<void> startTalk() async {
    if (_phase != HomePhase.idle) return;
    _errorMessage = '';
    _assistantMessage = '';
    _isContinuation = false;
    if (!await _recorder.hasPermission()) {
      _errorMessage = 'Abeg allow microphone make I fit hear you.';
      notifyListeners();
      return;
    }
    await _tts.stop();
    await _agent.discardPending();
    await _recorder.start();
    _setPhase(HomePhase.listening);
  }

  /// Continue an existing conversation (Gemma asked a clarifying question
  /// like "abeg tell me the price"; trader taps Reply and speaks the answer).
  Future<void> startReply() async {
    if (_phase != HomePhase.idle) return;
    if (!_agent.hasPendingConversation) {
      await startTalk();
      return;
    }
    _errorMessage = '';
    _assistantMessage = '';
    _isContinuation = true;
    if (!await _recorder.hasPermission()) {
      _errorMessage = 'Abeg allow microphone make I fit hear you.';
      notifyListeners();
      return;
    }
    await _tts.stop();
    await _recorder.start();
    _setPhase(HomePhase.listening);
  }

  Future<void> cancelTalk() async {
    if (_phase != HomePhase.listening) return;
    await _recorder.cancel();
    _setPhase(HomePhase.idle);
  }

  Future<void> stopTalk() async {
    if (_phase != HomePhase.listening) return;
    _setPhase(HomePhase.thinking);
    try {
      final chunks = await _recorder.stop();
      if (chunks.isEmpty) {
        _errorMessage = 'I no hear anything. Press am talk again.';
        _setPhase(HomePhase.idle);
        return;
      }
      // Don't gate on heardSpeech any more — some low-end phone mics
      // register speech below our threshold. Let Whisper/Gemma decide
      // whether the audio has content; if not, they'll return empty.
      final result = await _agent.runVoiceEntry(
        chunks,
        continueConversation: _isContinuation,
      );
      _isContinuation = false;
      if (result.undoable != null) {
        _pendingUndo = result.undoable;
        _undoNonce++;
      }
      _queue = confirmQueueFrom(result);
      _queueIndex = 0;
      if (_queue.isEmpty) {
        // Nothing staged. Either the model heard nothing, or it produced
        // a plain-text reply (usually a clarifying question). Treat true
        // rambles as errors; the rest as spoken assistant answers.
        final answer = result.answer.trim();
        final looksLikeRamble = answer.length > 600 ||
            RegExp(r'(\n\s*[-*#]|\*\*|##)').hasMatch(answer);
        if (answer.isEmpty || looksLikeRamble) {
          _errorMessage = 'I no understand your talk well. Try again '
              'small small.';
        } else {
          _assistantMessage = answer;
          await _tts.speak(answer);
        }
        _setPhase(HomePhase.idle);
      } else {
        _assistantMessage = '';
        _setPhase(HomePhase.confirm);
      }
    } catch (e) {
      _errorMessage = 'Something no work: $e';
      _setPhase(HomePhase.idle);
    }
  }

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
    await _finishQueueIfDone();
  }

  /// Drop only the current record and continue with the rest.
  Future<void> confirmSkip() async {
    if (currentConfirm == null) return;
    _queueIndex++;
    await _finishQueueIfDone();
  }

  Future<void> _finishQueueIfDone() async {
    if (_queueIndex < _queue.length) {
      notifyListeners();
      return;
    }
    if (_committedCount > 0) {
      final label = _committedCount == 1 ? 'record' : 'records';
      await _tts.speak(
          'I don write $_committedCount $label for your book. Correct!');
    }
    _queue = [];
    _queueIndex = 0;
    _committedCount = 0;
    _setPhase(HomePhase.idle);
  }

  Future<void> confirmNo() async {
    _queue = [];
    _queueIndex = 0;
    _committedCount = 0;
    _setPhase(HomePhase.idle);
    await startTalk();
  }

  /// Explicitly end a pending conversation from the UI (e.g. tap X on the
  /// assistant reply bubble).
  Future<void> dismissAssistant() async {
    _assistantMessage = '';
    await _agent.discardPending();
    notifyListeners();
  }

  void _setPhase(HomePhase phase) {
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _ledger.removeListener(notifyListeners);
    _silenceSubscription?.cancel();
    super.dispose();
  }
}
