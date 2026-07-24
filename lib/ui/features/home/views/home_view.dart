import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/app_settings.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/mic_widgets.dart';
import '../../settings/view_models/settings_view_model.dart';
import '../../settings/views/settings_view.dart';
import '../view_models/home_view_model.dart';

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});
  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    final isLocal = mode == AppMode.local;
    final color = isLocal ? OjaColors.gold : OjaColors.green;
    final label = isLocal ? 'Local' : 'Online';
    final icon = isLocal ? Icons.phone_android_rounded : Icons.cloud_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: OjaText.body(
                  size: 13, weight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _lastUndoNonce = 0;

  HomeViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _lastUndoNonce = viewModel.undoNonce;
    viewModel.addListener(_maybeShowUndoSnackbar);
  }

  @override
  void dispose() {
    viewModel.removeListener(_maybeShowUndoSnackbar);
    super.dispose();
  }

  void _maybeShowUndoSnackbar() {
    if (viewModel.undoNonce == _lastUndoNonce) return;
    _lastUndoNonce = viewModel.undoNonce;
    final action = viewModel.pendingUndo;
    if (action == null) return;
    // Post-frame so we don't tangle with the notifier's own frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: OjaColors.navy,
          behavior: SnackBarBehavior.floating,
          content: Text(
            action.description,
            style: OjaText.body(
                size: 15,
                weight: FontWeight.w700,
                color: OjaColors.cream),
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: OjaColors.gold,
            onPressed: viewModel.performUndo,
          ),
          onVisible: () {},
        ),
      );
    });
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _today {
    final now = DateTime.now();
    return '${_weekdays[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final settingsVm = context.watch<SettingsViewModel>();
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('OjaAI', style: OjaText.logo()),
                      Row(
                        children: [
                          _ModeChip(mode: settingsVm.current.mode),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.settings_rounded,
                                color: OjaColors.navy),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SettingsView(viewModel: settingsVm),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(_today, style: OjaText.body(size: 16)),
                  ),
                ),
                Expanded(child: Center(child: _centerContent())),
                if (viewModel.hasEntries) _totalsRow(),
              ],
            ),
            if (viewModel.currentConfirm != null)
              ConfirmOverlay(
                item: viewModel.currentConfirm!,
                onCorrect: viewModel.confirmYes,
                onTryAgain: viewModel.confirmNo,
                onSkip:
                    viewModel.confirmCount > 1 ? viewModel.confirmSkip : null,
                sourceLabel: viewModel.confirmCount > 1
                    ? 'Record ${viewModel.confirmNumber} of ${viewModel.confirmCount}'
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _centerContent() {
    switch (viewModel.phase) {
      case HomePhase.listening:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: viewModel.stopTalk,
              child: const PulsingCircle(
                color: OjaColors.gold,
                child: MicIcon(color: OjaColors.navy),
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(height: 44, child: Center(child: WaveformBars())),
            const SizedBox(height: 12),
            Text(
              'E dey hear you…',
              style: OjaText.body(
                  size: 24, weight: FontWeight.w700, color: OjaColors.navy),
            ),
            const SizedBox(height: 4),
            Text('Tap di mic when you don finish', style: OjaText.body(size: 16)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: viewModel.cancelTalk,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: OjaColors.red, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close_rounded,
                        size: 20, color: OjaColors.red),
                    const SizedBox(width: 6),
                    Text(
                      'Cancel am',
                      style: OjaText.body(
                          size: 17,
                          weight: FontWeight.w700,
                          color: OjaColors.red),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case HomePhase.thinking:
      case HomePhase.confirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: OjaColors.navyFaint, width: 3),
              ),
              child: const Center(child: ThinkingDots()),
            ),
            const SizedBox(height: 22),
            Text(
              'E dey write am…',
              style: OjaText.body(
                  size: 24, weight: FontWeight.w700, color: OjaColors.navy),
            ),
          ],
        );
      case HomePhase.idle:
        final showAssistant = viewModel.assistantMessage.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!viewModel.hasEntries && !showAssistant) ...[
                _emptyBookDoodle(),
                const SizedBox(height: 20),
                Text(
                  'Your book dey empty. Press di mic make you start your first record.',
                  textAlign: TextAlign.center,
                  style: OjaText.body(size: 21),
                ),
                const SizedBox(height: 24),
              ],
              if (showAssistant) ...[
                _assistantBubble(viewModel),
                const SizedBox(height: 22),
              ],
              GestureDetector(
                onTap: viewModel.hasPendingReply
                    ? viewModel.startReply
                    : viewModel.startTalk,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: viewModel.hasPendingReply
                        ? OjaColors.gold
                        : OjaColors.navy,
                    boxShadow: [
                      BoxShadow(
                        color: (viewModel.hasPendingReply
                                ? OjaColors.gold
                                : OjaColors.navy)
                            .withValues(alpha: 0.28),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                      const BoxShadow(
                        color: Color(0x121C2B4A),
                        spreadRadius: 14,
                      ),
                    ],
                  ),
                  child: Center(
                    child: MicIcon(
                      color: viewModel.hasPendingReply
                          ? OjaColors.navy
                          : OjaColors.cream,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                viewModel.hasPendingReply ? 'Press am, reply' : 'Press am, talk',
                style: OjaText.body(
                    size: 24, weight: FontWeight.w700, color: OjaColors.navy),
              ),
              if (viewModel.hasEntries && !showAssistant) ...[
                const SizedBox(height: 8),
                Text('Talk your sale or debt, we go write am',
                    style: OjaText.body()),
              ],
              if (viewModel.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      viewModel.errorMessage,
                      textAlign: TextAlign.center,
                      style: OjaText.body(size: 17, color: OjaColors.red),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _assistantBubble(HomeViewModel viewModel) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: const Border(
            left: BorderSide(color: OjaColors.gold, width: 6)),
        boxShadow: [
          BoxShadow(
            color: OjaColors.navy.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volume_up_rounded, color: OjaColors.navy),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                viewModel.assistantMessage,
                style: OjaText.body(size: 17, color: OjaColors.navy),
              ),
            ),
          ),
          GestureDetector(
            onTap: viewModel.dismissAssistant,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.close_rounded,
                  size: 20,
                  color: OjaColors.navy.withValues(alpha: 0.55)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── mode chip shown next to the settings gear ───────────
  // (kept below the main class as a private widget)

  Widget _emptyBookDoodle() {
    return Container(
      width: 150,
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: OjaColors.navy.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 24,
            child: Container(width: 2, color: OjaColors.marginRule),
          ),
          Positioned(
            top: 36,
            left: 36,
            child: Text('₦ ledger',
                style: OjaText.logo(size: 26, color: OjaColors.navy)),
          ),
        ],
      ),
    );
  }

  Widget _totalsRow() {
    final totals = viewModel.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: _totalCard(
              label: 'Today enta',
              symbol: '▲',
              amount: totals.todayIn,
              color: OjaColors.green,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _totalCard(
              label: 'Dem owe',
              symbol: '●',
              amount: totals.totalOwed,
              color: OjaColors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalCard({
    required String label,
    required String symbol,
    required int amount,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(bottom: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(symbol,
                  style: OjaText.body(
                      size: 20, weight: FontWeight.w800, color: color)),
              const SizedBox(width: 7),
              Text(label, style: OjaText.body()),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            child:
                Text(formatNaira(amount), style: OjaText.number(color: color)),
          ),
        ],
      ),
    );
  }
}
