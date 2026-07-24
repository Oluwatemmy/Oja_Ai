import 'ledger_entry.dart';

/// Something a voice command mutated and that we can reverse if the trader
/// taps "Undo" on the snackbar within a few seconds.
sealed class UndoableAction {
  const UndoableAction({required this.description});

  /// Short line shown in the snackbar, e.g. 'Deleted Mama Alex egg'.
  final String description;
}

/// Voice delete: restore the entry and any payments that were cascaded.
class DeletedEntryAction extends UndoableAction {
  const DeletedEntryAction({
    required super.description,
    required this.entry,
    required this.linkedPayments,
  });

  final LedgerEntry entry;
  final List<LedgerEntry> linkedPayments;
}

/// Voice edit: restore the entry to its pre-edit state.
class EditedEntryAction extends UndoableAction {
  const EditedEntryAction({
    required super.description,
    required this.previous,
  });

  final LedgerEntry previous;
}
