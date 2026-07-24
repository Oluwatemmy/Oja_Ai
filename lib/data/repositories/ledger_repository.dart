import 'package:flutter/foundation.dart';

import '../../domain/models/agent_result.dart';
import '../../domain/models/ledger_entry.dart';
import '../services/database_service.dart';

/// Single source of truth for the ledger. Notifies listeners after every
/// mutation so Home totals and the Ledger list stay in sync.
class LedgerRepository extends ChangeNotifier {
  LedgerRepository({required DatabaseService database}) : _database = database;

  final DatabaseService _database;
  int _idCounter = 0;

  List<LedgerEntry> _entries = [];
  LedgerTotals _totals = LedgerTotals.zero;

  List<LedgerEntry> get entries => List.unmodifiable(_entries);
  LedgerTotals get totals => _totals;

  Future<void> load() async {
    _entries = await _database.allEntries();
    _totals = await _database.totals();
    notifyListeners();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  Future<LedgerEntry> commitEntry(EntryProposal proposal) async {
    final entry = LedgerEntry(
      id: _newId(),
      item: proposal.item,
      party: proposal.party,
      amount: proposal.amount,
      type: proposal.type,
      createdAt: DateTime.now(),
    );
    await _database.insertEntry(entry);
    await load();
    return entry;
  }

  /// A repayment is two movements: the debt goes down AND the cash the
  /// trader just received enters the book as money-in (counts in
  /// "Today enta"). The money-in entry is linked so un-ticking reverses it.
  Future<LedgerEntry?> commitPayment(PaymentProposal proposal) async {
    final entry = await _database.entryById(proposal.entryId);
    if (entry == null) return null;
    final paid = proposal.amount.clamp(0, entry.amount);
    final remaining = entry.amount - paid;
    final updated =
        entry.copyWith(amount: remaining, settled: remaining == 0);
    await _database.updateEntry(updated);
    if (paid > 0) {
      await _database.insertEntry(LedgerEntry(
        id: _newId(),
        item: 'Payment — ${entry.item}',
        party: entry.party,
        amount: paid,
        type: EntryType.moneyIn,
        createdAt: DateTime.now(),
        linkedTo: entry.id,
      ));
    }
    await load();
    return updated;
  }

  Future<void> togglePaid(LedgerEntry entry) async {
    if (entry.type != EntryType.owe) return;
    if (!entry.settled) {
      // Tick: the debtor paid the whole outstanding amount right now.
      await commitPayment(PaymentProposal(
        entryId: entry.id,
        party: entry.party,
        item: entry.item,
        amount: entry.amount,
        outstanding: entry.amount,
      ));
    } else {
      // Un-tick: this debt was not actually paid — reverse every payment
      // recorded against it and restore the outstanding amount.
      final payments = await _database.entriesLinkedTo(entry.id);
      final repaid =
          payments.fold<int>(0, (sum, p) => sum + p.amount);
      await _database.deleteEntriesLinkedTo(entry.id);
      await _database.updateEntry(
        entry.copyWith(amount: entry.amount + repaid, settled: false),
      );
      await load();
    }
  }

  Future<List<LedgerEntry>> searchByParty(String query) =>
      _database.searchByParty(query);

  Future<LedgerEntry?> entryById(String id) => _database.entryById(id);

  Future<List<LedgerEntry>> entriesLinkedTo(String id) =>
      _database.entriesLinkedTo(id);

  Future<List<LedgerEntry>> entriesForParty(String party) =>
      _database.entriesForParty(party);

  /// Undo helper for delete: re-insert the entry and any payment rows that
  /// were cascaded off it.
  Future<void> restoreEntry(
    LedgerEntry entry,
    List<LedgerEntry> linkedPayments,
  ) async {
    await _database.insertEntry(entry);
    for (final p in linkedPayments) {
      await _database.insertEntry(p);
    }
    await load();
  }

  /// Undo helper for edit: overwrite the current entry with the pre-edit
  /// snapshot. Does NOT touch linked payments.
  Future<void> replaceEntry(LedgerEntry entry) async {
    await _database.updateEntry(entry);
    await load();
  }

  /// Overwrite any editable fields of an entry. Amount/type changes bubble
  /// straight to totals via load().
  Future<LedgerEntry?> editEntry(
    String id, {
    String? item,
    String? party,
    int? amount,
    EntryType? type,
  }) async {
    final existing = await _database.entryById(id);
    if (existing == null) return null;
    final updated = LedgerEntry(
      id: existing.id,
      item: item?.trim().isNotEmpty == true ? item!.trim() : existing.item,
      party:
          party?.trim().isNotEmpty == true ? party!.trim() : existing.party,
      amount: amount ?? existing.amount,
      type: type ?? existing.type,
      createdAt: existing.createdAt,
      settled: (amount ?? existing.amount) == 0 && existing.settled,
    );
    await _database.updateEntry(updated);
    await load();
    return updated;
  }

  /// Delete an entry AND any payment rows linked to it (so an owe row that
  /// was partially paid doesn't leave orphaned "Payment — X" money-in rows).
  Future<void> deleteEntry(String id) async {
    await _database.deleteEntriesLinkedTo(id);
    await _database.deleteEntry(id);
    await load();
  }

  Future<List<LedgerEntry>> outstandingDebts() async {
    final all = await _database.allEntries();
    return all
        .where((e) => e.type == EntryType.owe && !e.settled && e.amount > 0)
        .toList();
  }
}
