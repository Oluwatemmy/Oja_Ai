import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/gemma_service.dart';
import '../../../core/theme.dart';
import '../../home/view_models/home_view_model.dart';
import '../../home/views/home_view.dart';
import '../../ledger/view_models/ledger_view_model.dart';
import '../../ledger/views/ledger_view.dart';
import '../../snap/view_models/snap_view_model.dart';
import '../../snap/views/snap_view.dart';

enum OjaTab { talk, snap, ledger }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  OjaTab _tab = OjaTab.talk;

  /// Snap needs a vision-capable Gemma. Hidden when running Gemma 3 1B
  /// (text-only); the whole flow re-enables automatically for Gemma 4 builds.
  bool get _snapAvailable => GemmaService.supportsMultimodal;

  @override
  Widget build(BuildContext context) {
    final isSnap = _tab == OjaTab.snap;
    return Scaffold(
      backgroundColor: isSnap ? const Color(0xFF181A1E) : OjaColors.cream,
      body: SafeArea(
        top: !isSnap,
        bottom: false,
        child: switch (_tab) {
          OjaTab.talk => HomeView(viewModel: context.read<HomeViewModel>()),
          OjaTab.snap => SnapView(
              viewModel: context.read<SnapViewModel>(),
              onClose: () => setState(() => _tab = OjaTab.talk),
              onFinished: () => setState(() => _tab = OjaTab.ledger),
            ),
          OjaTab.ledger =>
            LedgerView(viewModel: context.read<LedgerViewModel>()),
        },
      ),
      bottomNavigationBar: isSnap ? null : _navBar(),
    );
  }

  Widget _navBar() {
    return Container(
      decoration: const BoxDecoration(
        color: OjaColors.cream,
        border: Border(
          top: BorderSide(color: Color(0x1F1C2B4A), width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _navItem(OjaTab.talk, Icons.mic_rounded, 'Talk'),
              const SizedBox(width: 56),
              if (_snapAvailable) ...[
                _navItem(OjaTab.snap, Icons.photo_camera_outlined, 'Snap'),
                const SizedBox(width: 56),
              ],
              _navItem(OjaTab.ledger, Icons.receipt_long_outlined, 'Ledger'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(OjaTab tab, IconData icon, String label) {
    final active = _tab == tab;
    final color = active ? OjaColors.navy : const Color(0x9E3A3A3A);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = tab),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 5),
          Text(
            label,
            style: OjaText.body(
              size: 18,
              color: color,
              weight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
