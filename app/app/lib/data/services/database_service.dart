import 'package:sqflite/sqflite.dart';

import '../../domain/models/ledger_entry.dart';

class DatabaseService {
  DatabaseService({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  final DatabaseFactory? _factory;
  final String? _path;
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final factory = _factory ?? databaseFactory;
    final path = _path ?? '${await factory.getDatabasesPath()}/ojaai.db';
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE entries(
            id TEXT PRIMARY KEY,
            item TEXT NOT NULL,
            party TEXT NOT NULL,
            amount INTEGER NOT NULL,
            type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            settled INTEGER NOT NULL DEFAULT 0,
            linked_to TEXT
          )
        '''),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE entries ADD COLUMN linked_to TEXT');
          }
        },
      ),
    );
    return _db!;
  }

  Future<void> insertEntry(LedgerEntry entry) async {
    final db = await _database;
    await db.insert('entries', entry.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateEntry(LedgerEntry entry) async {
    final db = await _database;
    await db.update('entries', entry.toDbMap(),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<List<LedgerEntry>> allEntries() async {
    final db = await _database;
    final rows = await db.query('entries', orderBy: 'created_at DESC');
    return rows.map(LedgerEntry.fromDbMap).toList();
  }

  Future<LedgerEntry?> entryById(String id) async {
    final db = await _database;
    final rows =
        await db.query('entries', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return LedgerEntry.fromDbMap(rows.first);
  }

  Future<List<LedgerEntry>> searchByParty(String query) async {
    final db = await _database;
    final rows = await db.query(
      'entries',
      where: 'party LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
    );
    return rows.map(LedgerEntry.fromDbMap).toList();
  }

  Future<void> deleteEntry(String id) async {
    final db = await _database;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LedgerEntry>> entriesForParty(String party) async {
    final db = await _database;
    final rows = await db.query(
      'entries',
      where: 'LOWER(party) = LOWER(?)',
      whereArgs: [party],
      orderBy: 'created_at DESC',
    );
    return rows.map(LedgerEntry.fromDbMap).toList();
  }

  Future<List<LedgerEntry>> entriesLinkedTo(String id) async {
    final db = await _database;
    final rows =
        await db.query('entries', where: 'linked_to = ?', whereArgs: [id]);
    return rows.map(LedgerEntry.fromDbMap).toList();
  }

  Future<void> deleteEntriesLinkedTo(String id) async {
    final db = await _database;
    await db.delete('entries', where: 'linked_to = ?', whereArgs: [id]);
  }

  Future<LedgerTotals> totals() async {
    final db = await _database;
    final startOfDay = DateTime.now();
    final dayStart =
        DateTime(startOfDay.year, startOfDay.month, startOfDay.day)
            .millisecondsSinceEpoch;
    final inRows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM entries WHERE type='in' AND created_at >= ?",
      [dayStart],
    );
    final oweRows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM entries WHERE type='owe' AND settled=0",
    );
    return LedgerTotals(
      todayIn: inRows.first['s'] as int,
      totalOwed: oweRows.first['s'] as int,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
