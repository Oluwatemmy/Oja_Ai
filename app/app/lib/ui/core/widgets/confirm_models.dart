import '../../../domain/models/agent_result.dart';

/// One item awaiting the trader's "Correct" tap.
class ConfirmItem {
  const ConfirmItem.entry(
    EntryProposal this.entry, {
    this.timingSummary,
    this.transcript,
  }) : payment = null;
  const ConfirmItem.payment(
    PaymentProposal this.payment, {
    this.timingSummary,
    this.transcript,
  }) : entry = null;

  final EntryProposal? entry;
  final PaymentProposal? payment;

  /// Attached to the FIRST item in a batch so the sheet can show it once.
  final String? timingSummary;

  /// The raw Whisper transcript — shown so the trader sees exactly what
  /// was heard. Only attached to the first item in the batch.
  final String? transcript;

  bool get isPayment => payment != null;
}

List<ConfirmItem> confirmQueueFrom(AgentResult result) {
  final timing = result.timing.summary;
  final transcript = result.transcript;
  final items = <ConfirmItem>[
    for (final e in result.entries) ConfirmItem.entry(e),
    for (final p in result.payments) ConfirmItem.payment(p),
  ];
  if (items.isEmpty) return items;
  final first = items.first;
  items[0] = first.isPayment
      ? ConfirmItem.payment(
          first.payment!,
          timingSummary: timing,
          transcript: transcript,
        )
      : ConfirmItem.entry(
          first.entry!,
          timingSummary: timing,
          transcript: transcript,
        );
  return items;
}
