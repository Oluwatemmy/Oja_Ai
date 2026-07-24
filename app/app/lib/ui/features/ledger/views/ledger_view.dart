import 'package:flutter/material.dart';

import '../../../../domain/models/ledger_entry.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/mic_widgets.dart';
import '../view_models/ledger_view_model.dart';
import 'edit_record_sheet.dart';

class LedgerView extends StatelessWidget {
  const LedgerView({super.key, required this.viewModel});

  final LedgerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('My Ledger',
                      style: OjaText.number(size: 26)),
                  Text('OjaAI', style: OjaText.logo(size: 26)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _askBar(),
            ),
            Expanded(child: _entriesList()),
          ],
        );
      },
    );
  }

  Widget _askBar() {
    switch (viewModel.askPhase) {
      case AskPhase.idle:
        return GestureDetector(
          onTap: viewModel.startAsk,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: OjaColors.navy,
              borderRadius: BorderRadius.circular(34),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: OjaColors.gold,
                  ),
                  child:
                      const Icon(Icons.mic_rounded, color: OjaColors.navy),
                ),
                const SizedBox(width: 14),
                Text(
                  'Ask your book anything',
                  style: OjaText.body(
                      size: 20,
                      weight: FontWeight.w700,
                      color: OjaColors.cream),
                ),
              ],
            ),
          ),
        );
      case AskPhase.listening:
        return GestureDetector(
          onTap: viewModel.finishAsk,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: OjaColors.gold,
              borderRadius: BorderRadius.circular(34),
            ),
            child: Row(
              children: [
                const SizedBox(
                    height: 30,
                    child: WaveformBars(height: 26, barWidth: 5)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'I dey hear… tap when you don talk finish',
                    style: OjaText.body(
                        size: 18,
                        weight: FontWeight.w700,
                        color: OjaColors.navy),
                  ),
                ),
                GestureDetector(
                  onTap: viewModel.cancelAsk,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: OjaColors.navy,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 22, color: OjaColors.cream),
                  ),
                ),
              ],
            ),
          ),
        );
      case AskPhase.thinking:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const ThinkingDots(dotSize: 12),
              const SizedBox(width: 14),
              Text('E dey check your book…',
                  style: OjaText.body(size: 18, weight: FontWeight.w700)),
            ],
          ),
        );
      case AskPhase.answer:
        return GestureDetector(
          onTap: viewModel.resetAsk,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: const Border(
                  left: BorderSide(color: OjaColors.gold, width: 6)),
              boxShadow: [
                BoxShadow(
                  color: OjaColors.navy.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        size: 22, color: OjaColors.ink),
                    const SizedBox(width: 10),
                    Text('OjaAI dey talk…', style: OjaText.body()),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  viewModel.answer,
                  style: OjaText.number(size: 22, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _entriesList() {
    final entries = viewModel.entries;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No record yet. Go press di mic make you start.',
            textAlign: TextAlign.center,
            style: OjaText.body(size: 20),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _entryRow(context, entries[index]),
    );
  }

  Widget _entryRow(BuildContext context, LedgerEntry entry) {
    final isIn = entry.type == EntryType.moneyIn;
    final settled = entry.settled;
    final color = settled
        ? OjaColors.ink.withValues(alpha: 0.45)
        : (isIn ? OjaColors.green : OjaColors.red);
    final tint = isIn ? OjaColors.greenTint : OjaColors.redTint;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => EditRecordSheet.show(context, entry),
        borderRadius: BorderRadius.circular(6),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 6)),
        boxShadow: [
          BoxShadow(
            color: OjaColors.navy.withValues(alpha: 0.09),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                settled ? '✓' : (isIn ? '▲' : '●'),
                style: OjaText.body(
                    size: 19, weight: FontWeight.w800, color: color),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OjaText.body(
                    size: 20,
                    weight: FontWeight.w700,
                    color: OjaColors.navy,
                  ).copyWith(
                    decoration: settled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '${entry.party} · ${_timeLabel(entry.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OjaText.body(size: 17),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                settled ? 'Paid' : formatNaira(entry.amount),
                style: OjaText.number(size: 22, color: color),
              ),
              Text(
                settled ? '' : (isIn ? 'Enta' : 'Owe'),
                style: OjaText.body(
                    size: 16, weight: FontWeight.w700, color: color),
              ),
            ],
          ),
          if (entry.type == EntryType.owe) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => viewModel.togglePaid(entry),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: settled ? OjaColors.green : Colors.white,
                  border: Border.all(
                    color: settled ? OjaColors.green : OjaColors.navyFaint,
                    width: 2,
                  ),
                ),
                child: settled
                    ? const Icon(Icons.check_rounded,
                        size: 20, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    final isToday = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    if (isToday) {
      final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour12:$minute ${time.hour >= 12 ? 'PM' : 'AM'}';
    }
    if (difference.inDays < 2) return 'Yesterday';
    return '${time.day}/${time.month}';
  }
}
