import 'ledger_entry.dart';
import 'undoable_action.dart';

/// A new record the model proposes to write into the ledger.
/// Nothing touches the database until the trader taps "Correct".
class EntryProposal {
  const EntryProposal({
    required this.item,
    required this.party,
    required this.amount,
    required this.type,
    this.caption = '',
  });

  final String item;
  final String party;
  final int amount;
  final EntryType type;

  /// What the model heard, e.g. 'You talk say: "Madam Ngozi buy 3 crate egg..."'.
  final String caption;

  EntryProposal withCaption(String caption) => EntryProposal(
        item: item,
        party: party,
        amount: amount,
        type: type,
        caption: caption,
      );
}

/// A payment the model proposes to apply against an outstanding debt.
class PaymentProposal {
  const PaymentProposal({
    required this.entryId,
    required this.party,
    required this.item,
    required this.amount,
    required this.outstanding,
    this.caption = '',
  });

  final String entryId;
  final String party;
  final String item;

  /// Amount being paid now, whole naira.
  final int amount;

  /// What was outstanding before this payment.
  final int outstanding;
  final String caption;

  int get remainingAfter => (outstanding - amount).clamp(0, outstanding);

  PaymentProposal withCaption(String caption) => PaymentProposal(
        entryId: entryId,
        party: party,
        item: item,
        amount: amount,
        outstanding: outstanding,
        caption: caption,
      );
}

/// Everything one agent run produced.
class AgentResult {
  const AgentResult({
    this.entries = const [],
    this.payments = const [],
    this.answer = '',
    this.timing = AgentTiming.zero,
    this.transcript = '',
    this.undoable,
  });

  final List<EntryProposal> entries;
  final List<PaymentProposal> payments;

  /// Final spoken/plain-text reply from the model (used for
  /// "Ask your book" answers and confirm-sheet captions).
  final String answer;

  final AgentTiming timing;

  /// The Whisper transcript that produced these proposals. Shown on the
  /// confirm sheet so the trader can see exactly what OjaAI heard.
  final String transcript;

  /// Set when the model directly mutated the ledger via delete_record or
  /// edit_record. The UI can offer an "Undo" snackbar to reverse it.
  final UndoableAction? undoable;

  bool get hasProposals => entries.isNotEmpty || payments.isNotEmpty;
}

/// Wall-clock latency of one agent run. All values are milliseconds.
class AgentTiming {
  const AgentTiming({
    required this.whisperMs,
    required this.chatSetupMs,
    required this.firstResponseMs,
    required this.totalMs,
    required this.toolRounds,
  });

  /// Time spent transcribing audio via Whisper.
  final int whisperMs;
  final int chatSetupMs;
  final int firstResponseMs;
  final int totalMs;
  final int toolRounds;

  static const zero = AgentTiming(
      whisperMs: 0,
      chatSetupMs: 0,
      firstResponseMs: 0,
      totalMs: 0,
      toolRounds: 0);

  String get summary => 'Total ${_s(totalMs)} · '
      'Whisper ${_s(whisperMs)} · Gemma ${_s(totalMs - whisperMs)} '
      '($toolRounds tool round${toolRounds == 1 ? '' : 's'})';

  static String _s(int ms) => ms < 1000
      ? '${ms}ms'
      : '${(ms / 1000).toStringAsFixed(1)}s';
}
