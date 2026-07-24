import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/mic_widgets.dart';
import '../view_models/snap_view_model.dart';

class SnapView extends StatefulWidget {
  const SnapView({
    super.key,
    required this.viewModel,
    required this.onClose,
    required this.onFinished,
  });

  final SnapViewModel viewModel;
  final VoidCallback onClose;

  /// Called when the whole snapped batch has been confirmed.
  final VoidCallback onFinished;

  @override
  State<SnapView> createState() => _SnapViewState();
}

class _SnapViewState extends State<SnapView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.initCamera();
    widget.viewModel.addListener(_onChanged);
  }

  void _onChanged() {
    if (widget.viewModel.finished) widget.onFinished();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onChanged);
    widget.viewModel.disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Container(
          color: const Color(0xFF181A1E),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: widget.onClose,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    OjaColors.cream.withValues(alpha: 0.14),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new,
                                  color: OjaColors.cream, size: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Snap your book',
                            style: OjaText.body(
                                size: 22,
                                weight: FontWeight.w700,
                                color: OjaColors.cream),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 6),
                        child: _viewfinder(viewModel),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 22, 0, 30),
                      child: Center(child: _shutterButton(viewModel)),
                    ),
                  ],
                ),
                if (viewModel.phase == SnapPhase.thinking)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xCC181A1E),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 140,
                              height: 140,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: OjaColors.cream,
                              ),
                              child: const Center(child: ThinkingDots()),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'E dey read your book…',
                              style: OjaText.body(
                                  size: 22,
                                  weight: FontWeight.w700,
                                  color: OjaColors.cream),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (viewModel.currentConfirm != null)
                  ConfirmOverlay(
                    item: viewModel.currentConfirm!,
                    onCorrect: viewModel.confirmYes,
                    onTryAgain: viewModel.confirmNo,
                    onSkip: viewModel.confirmCount > 1
                        ? viewModel.confirmSkip
                        : null,
                    sourceLabel:
                        'From your book — record ${viewModel.confirmNumber} of ${viewModel.confirmCount}',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _viewfinder(SnapViewModel viewModel) {
    final controller = viewModel.controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            CameraPreview(controller)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2D33), Color(0xFF1E2126)],
                ),
              ),
            ),
          if (viewModel.phase == SnapPhase.error)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      viewModel.errorMessage,
                      textAlign: TextAlign.center,
                      style: OjaText.body(
                          size: 19, color: OjaColors.cream),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: viewModel.retryAfterError,
                      style: FilledButton.styleFrom(
                          backgroundColor: OjaColors.gold),
                      child: Text('Try again',
                          style: OjaText.body(
                              size: 18,
                              weight: FontWeight.w800,
                              color: OjaColors.navy)),
                    ),
                  ],
                ),
              ),
            )
          else if (viewModel.phase == SnapPhase.ready)
            Align(
              alignment: const Alignment(0, -0.1),
              child: Text(
                'Hold your book steady inside di frame',
                style: OjaText.body(
                    size: 20,
                    color: OjaColors.cream.withValues(alpha: 0.75)),
              ),
            ),
          _corner(top: true, left: true),
          _corner(top: true, left: false),
          _corner(top: false, left: true),
          _corner(top: false, left: false),
        ],
      ),
    );
  }

  Widget _corner({required bool top, required bool left}) {
    const side = BorderSide(color: OjaColors.gold, width: 4);
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          border: Border(
            top: top ? side : BorderSide.none,
            bottom: top ? BorderSide.none : side,
            left: left ? side : BorderSide.none,
            right: left ? BorderSide.none : side,
          ),
        ),
      ),
    );
  }

  Widget _shutterButton(SnapViewModel viewModel) {
    final enabled = viewModel.phase == SnapPhase.ready;
    return GestureDetector(
      onTap: enabled ? viewModel.shutter : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: OjaColors.cream, width: 5),
          ),
          child: Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: OjaColors.cream,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
