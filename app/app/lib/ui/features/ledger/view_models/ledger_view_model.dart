import 'package:flutter/foundation.dart';

import '../../../../data/repositories/agent_repository.dart';
import '../../../../data/repositories/ledger_repository.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../../data/services/tts_service.dart';
import '../../../../domain/models/ledger_entry.dart';

enum AskPhase { idle, listening, thinking, answer }

class LedgerViewModel extends ChangeNotifier {
  LedgerViewModel({
    required AgentRepository agent,
    required LedgerRepository ledger,
    required AudioRecorderService recorder,
    required TtsService tts,
  })  : _agent = agent,
        _ledger = ledger,
        _recorder = recorder,
        _tts = tts {
    _ledger.addListener(notifyListeners);
  }

  final AgentRepository _agent;
  final LedgerRepository _ledger;
  final AudioRecorderService _recorder;
  final TtsService _tts;

  AskPhase _askPhase = AskPhase.idle;
  AskPhase get askPhase => _askPhase;

  String _answer = '';
  String get answer => _answer;

  List<LedgerEntry> get entries => _ledger.entries;
  LedgerTotals get totals => _ledger.totals;

  Future<void> startAsk() async {
    if (_askPhase == AskPhase.listening) {
      await finishAsk();
      return;
    }
    if (_askPhase != AskPhase.idle && _askPhase != AskPhase.answer) return;
    if (!await _recorder.hasPermission()) return;
    await _tts.stop();
    await _recorder.start();
    _askPhase = AskPhase.listening;
    notifyListeners();
  }

  Future<void> cancelAsk() async {
    if (_askPhase != AskPhase.listening) return;
    await _recorder.cancel();
    _askPhase = AskPhase.idle;
    notifyListeners();
  }

  Future<void> finishAsk() async {
    if (_askPhase != AskPhase.listening) return;
    _askPhase = AskPhase.thinking;
    notifyListeners();
    try {
      final chunks = await _recorder.stop();
      if (chunks.isEmpty) {
        _answer = 'I no hear anything. Try ask am again.';
        _askPhase = AskPhase.answer;
        notifyListeners();
        return;
      }
      final result = await _agent.runQuestion(chunks);
      _answer = result.answer.isEmpty
          ? 'I no fit answer dat one now. Try again.'
          : result.answer;
      _askPhase = AskPhase.answer;
      notifyListeners();
      await _tts.speak(_answer);
    } catch (e) {
      _answer = 'Something no work: $e';
      _askPhase = AskPhase.answer;
      notifyListeners();
    }
  }

  void resetAsk() {
    _askPhase = AskPhase.idle;
    _answer = '';
    notifyListeners();
  }

  Future<void> togglePaid(LedgerEntry entry) => _ledger.togglePaid(entry);

  @override
  void dispose() {
    _ledger.removeListener(notifyListeners);
    super.dispose();
  }
}
