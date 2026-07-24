import 'package:flutter/material.dart';

import '../../../domain/models/ledger_entry.dart';
import '../theme.dart';
import 'confirm_models.dart';

/// Receipt-style confirmation overlay: dark scrim + zigzag-top white sheet
/// with ruled paper lines, big amount, and Correct / Try again buttons.
class ConfirmOverlay extends StatelessWidget {
  const ConfirmOverlay({
    super.key,
    required this.item,
    required this.onCorrect,
    required this.onTryAgain,
    this.onSkip,
    this.badgeText,
    this.sourceLabel,
  });

  final ConfirmItem item;
  final VoidCallback onCorrect;
  final VoidCallback onTryAgain;

  /// Shown on multi-record queues: drop only this record, keep the rest.
  final VoidCallback? onSkip;
  final String? badgeText;

  /// e.g. "From your book — record 2 of 3".
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: OjaColors.navy.withValues(alpha: 0.45)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => FractionalTranslation(
              translation: Offset(0, value),
              child: child,
            ),
            child: _ReceiptSheet(
              item: item,
              onCorrect: onCorrect,
              onTryAgain: onTryAgain,
              onSkip: onSkip,
              badgeText: badgeText,
              sourceLabel: sourceLabel,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({
    required this.item,
    required this.onCorrect,
    required this.onTryAgain,
    this.onSkip,
    this.badgeText,
    this.sourceLabel,
  });

  final ConfirmItem item;
  final VoidCallback onCorrect;
  final VoidCallback onTryAgain;
  final VoidCallback? onSkip;
  final String? badgeText;
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final isPayment = item.isPayment;
    final entry = item.entry;
    final payment = item.payment;

    final title = isPayment ? 'Payment — ${payment!.item}' : entry!.item;
    final party = isPayment ? payment!.party : entry!.party;
    final amount = isPayment ? payment!.amount : entry!.amount;
    final caption = isPayment ? payment!.caption : entry!.caption;
    final isIn = !isPayment && entry!.type == EntryType.moneyIn;

    final badgeColor =
        isPayment ? OjaColors.green : (isIn ? OjaColors.green : OjaColors.red);
    final badgeTint =
        isPayment ? OjaColors.greenTint : (isIn ? OjaColors.greenTint : OjaColors.redTint);
    final badgeLabel = badgeText ??
        (isPayment ? '✓ Don pay' : (isIn ? '▲ Money enta' : '● Dem owe you'));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ZigzagEdge(),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(26, 6, 26, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sourceLabel != null) ...[
                Center(
                  child: Text(
                    sourceLabel!.toUpperCase(),
                    style: OjaText.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: OjaColors.ink,
                    ).copyWith(letterSpacing: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: OjaColors.marginRule, width: 2),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 8, 0, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: OjaText.body(
                        size: 22,
                        weight: FontWeight.w700,
                        color: OjaColors.navy,
                      ),
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 14,
                      children: [
                        Text(
                          formatNaira(amount),
                          style: OjaText.number(size: 52),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeLabel,
                            style: OjaText.body(
                              size: 19,
                              weight: FontWeight.w800,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(party, style: OjaText.body(size: 20)),
                    if (isPayment)
                      Text(
                        'E remain ${formatNaira(payment!.remainingAfter)}',
                        style: OjaText.body(
                          size: 18,
                          weight: FontWeight.w700,
                          color: OjaColors.red,
                        ),
                      ),
                  ],
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        size: 22, color: OjaColors.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(caption, style: OjaText.body(size: 18)),
                    ),
                  ],
                ),
              ],
              if (item.transcript != null && item.transcript!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x111C2B4A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.hearing_rounded,
                          size: 18, color: OjaColors.ink),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '"${item.transcript!}"',
                          style: OjaText.body(
                            size: 15,
                            color: const Color(0xCC3A3A3A),
                          ).copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (item.timingSummary != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.speed_rounded,
                        size: 16, color: OjaColors.ink),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.timingSummary!,
                        style: OjaText.body(
                          size: 13,
                          color: const Color(0x993A3A3A),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    flex: 14,
                    child: _SheetButton(
                      onTap: onCorrect,
                      background: OjaColors.green,
                      foreground: Colors.white,
                      borderColor: null,
                      icon: Icons.check_rounded,
                      label: 'Correct',
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 10,
                    child: _SheetButton(
                      onTap: onTryAgain,
                      background: Colors.white,
                      foreground: OjaColors.red,
                      borderColor: OjaColors.red,
                      icon: Icons.close_rounded,
                      label: 'Try again',
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              if (onSkip != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    onTap: onSkip,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 6),
                      child: Text(
                        'Skip only dis one →',
                        style: OjaText.body(
                          size: 18,
                          weight: FontWeight.w700,
                          color: OjaColors.ink,
                        ).copyWith(decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.icon,
    required this.label,
    required this.fontSize,
  });

  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final IconData icon;
  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!, width: 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 28),
              const SizedBox(width: 10),
              Text(
                label,
                style: OjaText.body(
                  size: fontSize,
                  weight: FontWeight.w800,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The torn-receipt zigzag top edge.
class _ZigzagEdge extends StatelessWidget {
  const _ZigzagEdge();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 14),
      painter: _ZigzagPainter(),
    );
  }
}

class _ZigzagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()..moveTo(0, size.height);
    const toothWidth = 18.0;
    var x = 0.0;
    while (x < size.width) {
      path.lineTo(x + toothWidth / 2, 0);
      path.lineTo(x + toothWidth, size.height);
      x += toothWidth;
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
