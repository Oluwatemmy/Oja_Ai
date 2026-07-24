import 'package:flutter_test/flutter_test.dart';
import 'package:ojaai/data/repositories/ledger_repository.dart';
import 'package:ojaai/data/services/database_service.dart';
import 'package:ojaai/domain/models/agent_result.dart';
import 'package:ojaai/domain/models/ledger_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerRepository repository;
  late DatabaseService database;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = DatabaseService(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = LedgerRepository(database: database);
    await repository.load();
  });

  tearDown(() async {
    await database.close();
  });

  test('commitEntry stores a sale and updates totals', () async {
    await repository.commitEntry(const EntryProposal(
      item: '3 crate egg',
      party: 'Madam Ngozi',
      amount: 5400,
      type: EntryType.moneyIn,
    ));

    expect(repository.entries, hasLength(1));
    expect(repository.totals.todayIn, 5400);
    expect(repository.totals.totalOwed, 0);
  });

  test('commitEntry stores a debt and outstanding total tracks it', () async {
    await repository.commitEntry(const EntryProposal(
      item: '2 wrapper',
      party: 'Iya Risi',
      amount: 9000,
      type: EntryType.owe,
    ));

    expect(repository.totals.totalOwed, 9000);
    final debts = await repository.outstandingDebts();
    expect(debts, hasLength(1));
    expect(debts.single.party, 'Iya Risi');
  });

  test('commitPayment reduces the debt and settles at zero', () async {
    final entry = await repository.commitEntry(const EntryProposal(
      item: 'Sewing money',
      party: 'Sister Bola',
      amount: 4200,
      type: EntryType.owe,
    ));

    await repository.commitPayment(PaymentProposal(
      entryId: entry.id,
      party: entry.party,
      item: entry.item,
      amount: 300,
      outstanding: entry.amount,
    ));
    expect(repository.totals.totalOwed, 3900);

    await repository.commitPayment(PaymentProposal(
      entryId: entry.id,
      party: entry.party,
      item: entry.item,
      amount: 3900,
      outstanding: 3900,
    ));
    expect(repository.totals.totalOwed, 0);
    final updated = await repository.entryById(entry.id);
    expect(updated!.settled, isTrue);
  });

  test('overpayment clamps at zero, never negative', () async {
    final entry = await repository.commitEntry(const EntryProposal(
      item: '1 bag rice',
      party: 'Bros Sunday',
      amount: 1000,
      type: EntryType.owe,
    ));

    await repository.commitPayment(PaymentProposal(
      entryId: entry.id,
      party: entry.party,
      item: entry.item,
      amount: 5000,
      outstanding: entry.amount,
    ));

    final updated = await repository.entryById(entry.id);
    expect(updated!.amount, 0);
    expect(updated.settled, isTrue);
  });

  test('repayment cash shows up as money-in', () async {
    final entry = await repository.commitEntry(const EntryProposal(
      item: 'Rice balance',
      party: 'Nonso',
      amount: 2000,
      type: EntryType.owe,
    ));

    await repository.commitPayment(PaymentProposal(
      entryId: entry.id,
      party: entry.party,
      item: entry.item,
      amount: 2000,
      outstanding: entry.amount,
    ));

    expect(repository.totals.totalOwed, 0);
    expect(repository.totals.todayIn, 2000);
    final paymentEntries = repository.entries
        .where((e) => e.type == EntryType.moneyIn)
        .toList();
    expect(paymentEntries, hasLength(1));
    expect(paymentEntries.single.item, 'Payment — Rice balance');
    expect(paymentEntries.single.linkedTo, entry.id);
  });

  test('un-ticking a debt reverses its payments', () async {
    final entry = await repository.commitEntry(const EntryProposal(
      item: 'Wrapper',
      party: 'Iya Risi',
      amount: 9000,
      type: EntryType.owe,
    ));

    await repository.togglePaid(entry); // tick: fully paid
    expect(repository.totals.todayIn, 9000);
    expect(repository.totals.totalOwed, 0);

    final settled = await repository.entryById(entry.id);
    await repository.togglePaid(settled!); // un-tick: reverse
    expect(repository.totals.todayIn, 0);
    expect(repository.totals.totalOwed, 9000);
    final restored = await repository.entryById(entry.id);
    expect(restored!.amount, 9000);
    expect(restored.settled, isFalse);
  });

  test('togglePaid settles and un-settles a debt', () async {
    final entry = await repository.commitEntry(const EntryProposal(
      item: 'Garri 2 paint',
      party: 'Mama Tobi',
      amount: 3000,
      type: EntryType.owe,
    ));

    await repository.togglePaid(entry);
    var updated = await repository.entryById(entry.id);
    expect(updated!.settled, isTrue);
    expect(repository.totals.totalOwed, 0);
  });

  test('searchByParty finds partial name matches', () async {
    await repository.commitEntry(const EntryProposal(
      item: '2 basket tomato',
      party: 'Mama Chidi',
      amount: 6000,
      type: EntryType.moneyIn,
    ));

    final matches = await repository.searchByParty('Chidi');
    expect(matches, hasLength(1));
    expect(matches.single.item, '2 basket tomato');
  });
}
