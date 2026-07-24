import 'package:flutter/material.dart';

import '../../../../domain/models/app_settings.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/mic_widgets.dart';
import '../view_models/setup_view_model.dart';

/// First-launch: pick local vs online, enter OpenRouter key if online,
/// download the right models, land on the app.
class SetupView extends StatelessWidget {
  const SetupView({super.key, required this.viewModel});

  final SetupViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OjaColors.navy,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height - 100,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Center(
                          child: Text('OjaAI',
                              style: OjaText.logo(
                                  size: 60, color: OjaColors.cream))),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'Talk your market, we go write am.',
                          style: OjaText.body(
                              size: 19, color: const Color(0xB3F7F1E3)),
                        ),
                      ),
                      const SizedBox(height: 40),
                      ..._content(context),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    switch (viewModel.phase) {
      case SetupPhase.loading:
        return const [
          Center(child: CircularProgressIndicator(color: OjaColors.gold)),
        ];
      case SetupPhase.pickMode:
        return _pickMode();
      case SetupPhase.enterApiKeys:
        return _enterApiKeys(context);
      case SetupPhase.needsDownload:
        return _readyToDownload();
      case SetupPhase.downloadingGemma:
        return _downloading();
      case SetupPhase.loadingModel:
        return [
          const Center(child: ThinkingDots()),
          const SizedBox(height: 20),
          Center(
            child: Text('E dey arrange di brain…',
                style: OjaText.body(
                    size: 20,
                    weight: FontWeight.w700,
                    color: OjaColors.cream)),
          ),
        ];
      case SetupPhase.error:
        return _error();
      case SetupPhase.ready:
        return [];
    }
  }

  List<Widget> _pickMode() => [
        Text(
          'How do you want OjaAI to think?',
          textAlign: TextAlign.center,
          style: OjaText.body(
              size: 20, weight: FontWeight.w700, color: OjaColors.cream),
        ),
        const SizedBox(height: 20),
        _ModeCard(
          title: 'On my phone',
          subtitle: 'Gemma 4 E4B run for your phone. No data needed. '
              'Best privacy. ~4.3 GB one-time download.',
          icon: Icons.phone_android_rounded,
          onTap: viewModel.pickLocal,
          accent: OjaColors.gold,
        ),
        const SizedBox(height: 14),
        _ModeCard(
          title: 'Online (Gemma 4 31B)',
          subtitle: 'Bigger brain via OpenRouter + Groq for voice. Faster '
              'and sharper, needs internet + 2 API keys. No downloads.',
          icon: Icons.cloud_outlined,
          onTap: viewModel.pickOnline,
          accent: OjaColors.green,
        ),
      ];

  List<Widget> _enterApiKeys(BuildContext context) => [
        Text(
          'Set your API keys',
          textAlign: TextAlign.center,
          style: OjaText.body(
              size: 20, weight: FontWeight.w700, color: OjaColors.cream),
        ),
        const SizedBox(height: 8),
        Text(
          'Online mode needs OpenRouter (brain) + Groq (ear). Both are '
          'kept private on your phone.',
          textAlign: TextAlign.center,
          style: OjaText.body(size: 14, color: const Color(0x99F7F1E3)),
        ),
        const SizedBox(height: 18),
        _keyLabel('OpenRouter key (Gemma 4 31B)'),
        _keyInput(
          hint: viewModel.settings.openRouterApiKey.isNotEmpty
              ? 'sk-or-… (saved)'
              : 'sk-or-…',
          initial: viewModel.apiKeyInput,
          onChanged: (v) => viewModel.apiKeyInput = v,
        ),
        const SizedBox(height: 14),
        _keyLabel('Groq key (Whisper transcription)'),
        _keyInput(
          hint: viewModel.settings.groqApiKey.isNotEmpty
              ? 'gsk_… (saved)'
              : 'gsk_…',
          initial: viewModel.groqKeyInput,
          onChanged: (v) => viewModel.groqKeyInput = v,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed:
              viewModel.testingKey ? null : viewModel.submitApiKeys,
          style: FilledButton.styleFrom(
            backgroundColor: OjaColors.gold,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28)),
          ),
          child: viewModel.testingKey
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: OjaColors.navy,
                    strokeWidth: 2.5,
                  ),
                )
              : Text('Save + test',
                  style: OjaText.body(
                      size: 20,
                      weight: FontWeight.w800,
                      color: OjaColors.navy)),
        ),
        if (viewModel.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            viewModel.errorMessage,
            textAlign: TextAlign.center,
            style: OjaText.body(size: 15, color: const Color(0xFFF0A08C)),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: viewModel.pickLocal,
          child: Text(
            '← Use on-device instead',
            style: OjaText.body(size: 15, color: const Color(0xB3F7F1E3)),
          ),
        ),
      ];

  Widget _keyLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(
          text.toUpperCase(),
          style: OjaText.body(
            size: 12,
            weight: FontWeight.w800,
            color: const Color(0xB3F7F1E3),
          ).copyWith(letterSpacing: 0.6),
        ),
      );

  Widget _keyInput({
    required String hint,
    required String initial,
    required ValueChanged<String> onChanged,
  }) =>
      TextField(
        controller: TextEditingController(text: initial)
          ..selection = TextSelection.collapsed(offset: initial.length),
        onChanged: onChanged,
        obscureText: true,
        style: OjaText.body(size: 16, color: OjaColors.cream),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0x22F7F1E3),
          hintText: hint,
          hintStyle: OjaText.body(size: 15, color: const Color(0x66F7F1E3)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );

  List<Widget> _readyToDownload() {
    final settings = viewModel.settings;
    final isLocal = settings.mode == AppMode.local;
    final description = isLocal
        ? 'One time only: we go download di brain (Gemma 4 E4B, ~4.3 GB) '
            'put inside your phone. After dat one, everything dey work '
            'offline — no data needed.'
        : 'Online mode ready — nothing to download. Voice → Groq Whisper '
            '(cloud, fast) → Gemma 4 31B on OpenRouter.';
    return [
      Text(
        description,
        textAlign: TextAlign.center,
        style: OjaText.body(size: 18, color: OjaColors.cream),
      ),
      const SizedBox(height: 16),
      if (isLocal) ...[
        _sizeLine('🧠 Gemma 4 E4B', '~4.3 GB'),
        _sizeLine('Phone RAM needed', '8 GB+'),
      ] else ...[
        _sizeLine('🎤 Groq Whisper', 'cloud (no download)'),
        _sizeLine('🧠 Gemma 4 31B', 'cloud (no download)'),
      ],
      const SizedBox(height: 22),
      FilledButton(
        onPressed: viewModel.download,
        style: FilledButton.styleFrom(
          backgroundColor: OjaColors.gold,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30)),
        ),
        child: Text('Download am',
            style: OjaText.body(
                size: 22, weight: FontWeight.w800, color: OjaColors.navy)),
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          'Use WiFi if you get am.',
          style: OjaText.body(size: 15, color: const Color(0x99F7F1E3)),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: viewModel.switchToOtherMode,
          child: Text(
            isLocal
                ? '← Use online mode instead'
                : '← Use on-device mode instead',
            style: OjaText.body(size: 15, color: const Color(0xB3F7F1E3)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _downloading() => [
        Text(
          viewModel.progressLabel,
          textAlign: TextAlign.center,
          style: OjaText.body(
              size: 20, weight: FontWeight.w700, color: OjaColors.cream),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: viewModel.progress / 100,
            minHeight: 14,
            backgroundColor: const Color(0x33F7F1E3),
            color: OjaColors.gold,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'No close di app. E fit take small time.',
            style: OjaText.body(size: 15, color: const Color(0x99F7F1E3)),
          ),
        ),
      ];

  List<Widget> _error() => [
        Text(
          viewModel.errorMessage,
          textAlign: TextAlign.center,
          style: OjaText.body(size: 18, color: const Color(0xFFF0A08C)),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: viewModel.start,
          style: FilledButton.styleFrom(
            backgroundColor: OjaColors.gold,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
          ),
          child: Text('Try again',
              style: OjaText.body(
                  size: 22, weight: FontWeight.w800, color: OjaColors.navy)),
        ),
      ];

  Widget _sizeLine(String label, String size) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: OjaText.body(size: 16, color: OjaColors.cream)),
            Text(size,
                style: OjaText.body(
                    size: 16,
                    weight: FontWeight.w700,
                    color: OjaColors.gold)),
          ],
        ),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x14F7F1E3),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.22),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: OjaText.body(
                            size: 18,
                            weight: FontWeight.w800,
                            color: OjaColors.cream)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: OjaText.body(
                            size: 14, color: const Color(0xB3F7F1E3))),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: OjaColors.cream, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
