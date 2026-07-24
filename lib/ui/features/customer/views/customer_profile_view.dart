import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/ledger_repository.dart';
import '../../../../domain/models/ledger_entry.dart';
import '../../../core/theme.dart';

/// Everything the trader has ever recorded for one customer, plus quick
/// bulk actions (mark all debts paid, delete every record). Reached from
/// the edit sheet's "See history" button and from any tap on a party name.
class CustomerProfileView extends StatelessWidget {
  const CustomerProfileView({super.key, required this.partyName});

  final String partyName;

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerRepository>();
    final entries = ledger.entries
        .where((e) => e.party.toLowerCase() == partyName.toLowerCase())
        .toList();
    final moneyIn = entries
        .where((e) => e.type == EntryType.moneyIn)
        .fold<int>(0, (s, e) => s + e.amount);
    final outstanding = entries
        .where((e) => e.type == EntryType.owe && !e.settled)
        .fold<int>(0, (s, e) => s + e.amount);
    final debts = entries
        .where((e) => e.type == EntryType.owe && !e.settled)
        .toList();

    return Scaffold(
      backgroundColor: OjaColors.cream,
      appBar: AppBar(
        backgroundColor: OjaColors.cream,
        elevation: 0,
        iconTheme: const IconThemeData(color: OjaColors.navy),
        title: Text(partyName,
            style: OjaText.number(size: 22, color: OjaColors.navy)),
        actions: [
          if (debts.isNotEmpty)
            IconButton(
              tooltip: 'Mark all paid',
              icon: const Icon(Icons.done_all_rounded,
                  color: OjaColors.green),
              onPressed: () => _confirmMarkAllPaid(context, ledger, debts),
            ),
          IconButton(
            tooltip: 'Delete all records',
            icon: const Icon(Icons.delete_outline_rounded,
                color: OjaColors.red),
            onPressed: entries.isEmpty
                ? null
                : () => _confirmDeleteAll(context, ledger, entries),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'No record for $partyName yet.',
                style: OjaText.body(size: 18),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Money enta',
                        symbol: '▲',
                        amount: moneyIn,
                        color: OjaColors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'E dey owe',
                        symbol: '●',
                        amount: outstanding,
                        color: OjaColors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('ALL RECORDS',
                    style: OjaText.body(
                      size: 13,
                      weight: FontWeight.w800,
                      color: OjaColors.ink,
                    ).copyWith(letterSpacing: 0.8)),
                const SizedBox(height: 10),
                for (final e in entries) ...[
                  _RecordRow(entry: e),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmMarkAllPaid(
    BuildContext context,
    LedgerRepository ledger,
    List<LedgerEntry> debts,
  ) async {
    final ok = await _yesNo(
      context,
      title: 'Mark all paid?',
      body: '$partyName get ${debts.length} debt. All of them go show as paid.',
      confirmLabel: 'Mark all paid',
      confirmColor: OjaColors.green,
    );
    if (!ok) return;
    for (final d in debts) {
      await ledger.togglePaid(d);
    }
  }

  Future<void> _confirmDeleteAll(
    BuildContext context,
    LedgerRepository ledger,
    List<LedgerEntry> entries,
  ) async {
    final navigator = Navigator.of(context);
    final ok = await _yesNo(
      context,
      title: 'Delete everything?',
      body: 'You go lose ${entries.length} record for $partyName. This '
          'no fit undo.',
      confirmLabel: 'Delete all',
      confirmColor: OjaColors.red,
    );
    if (!ok) return;
    for (final e in entries) {
      await ledger.deleteEntry(e.id);
    }
    navigator.pop();
  }

  Future<bool> _yesNo(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(title, style: OjaText.number(size: 20)),
            content: Text(body, style: OjaText.body(size: 16)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('Cancel',
                    style: OjaText.body(
                        size: 16,
                        weight: FontWeight.w700,
                        color: OjaColors.ink)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(backgroundColor: confirmColor),
                child: Text(confirmLabel,
                    style: OjaText.body(
                        size: 16,
                        weight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.symbol,
    required this.amount,
    required this.color,
  });

  final String label;
  final String symbol;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(bottom: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(symbol,
                  style: OjaText.body(
                      size: 18, weight: FontWeight.w800, color: color)),
              const SizedBox(width: 6),
              Text(label, style: OjaText.body(size: 15)),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(formatNaira(amount),
                style: OjaText.number(size: 26, color: color)),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final isIn = entry.type == EntryType.moneyIn;
    final color = entry.settled
        ? OjaColors.ink.withValues(alpha: 0.5)
        : (isIn ? OjaColors.green : OjaColors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.item,
                  style: OjaText.body(
                      size: 17,
                      weight: FontWeight.w700,
                      color: OjaColors.navy),
                ),
                Text(_dateLabel(entry.createdAt),
                    style: OjaText.body(size: 14)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(entry.settled ? 'Paid' : formatNaira(entry.amount),
                  style: OjaText.number(size: 18, color: color)),
              Text(
                entry.settled ? '' : (isIn ? 'Enta' : 'Owe'),
                style: OjaText.body(
                    size: 13, weight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime t) {
    return '${t.day}/${t.month}/${t.year}';
  }
}
