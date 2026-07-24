enum EntryType { moneyIn, owe }

extension EntryTypeCodec on EntryType {
  String get code => this == EntryType.moneyIn ? 'in' : 'owe';

  static EntryType fromCode(String code) =>
      code == 'in' ? EntryType.moneyIn : EntryType.owe;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.item,
    required this.party,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.settled = false,
    this.linkedTo,
  });

  final String id;
  final String item;
  final String party;

  /// Whole naira. For [EntryType.owe] this is the amount still outstanding.
  final int amount;
  final EntryType type;
  final DateTime createdAt;
  final bool settled;

  /// For money-in entries created by a debt repayment: the id of the owe
  /// entry it pays down. Lets un-ticking a debt reverse its payments.
  final String? linkedTo;

  LedgerEntry copyWith({int? amount, bool? settled}) => LedgerEntry(
        id: id,
        item: item,
        party: party,
        amount: amount ?? this.amount,
        type: type,
        createdAt: createdAt,
        settled: settled ?? this.settled,
        linkedTo: linkedTo,
      );

  Map<String, Object?> toDbMap() => {
        'id': id,
        'item': item,
        'party': party,
        'amount': amount,
        'type': type.code,
        'created_at': createdAt.millisecondsSinceEpoch,
        'settled': settled ? 1 : 0,
        'linked_to': linkedTo,
      };

  factory LedgerEntry.fromDbMap(Map<String, Object?> map) => LedgerEntry(
        id: map['id'] as String,
        item: map['item'] as String,
        party: map['party'] as String,
        amount: map['amount'] as int,
        type: EntryTypeCodec.fromCode(map['type'] as String),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        settled: (map['settled'] as int) == 1,
        linkedTo: map['linked_to'] as String?,
      );
}

class LedgerTotals {
  const LedgerTotals({required this.todayIn, required this.totalOwed});

  final int todayIn;
  final int totalOwed;

  static const zero = LedgerTotals(todayIn: 0, totalOwed: 0);
}
