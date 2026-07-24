import 'package:flutter/material.dart';

import '../../../../domain/models/app_settings.dart';
import '../../../core/theme.dart';
import '../view_models/settings_view_model.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OjaColors.cream,
      appBar: AppBar(
        backgroundColor: OjaColors.cream,
        elevation: 0,
        iconTheme: const IconThemeData(color: OjaColors.navy),
        title: Text('Settings',
            style: OjaText.number(size: 22, color: OjaColors.navy)),
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final s = viewModel.current;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _SectionLabel('Where does OjaAI think?'),
              _ModeTile(
                label: 'On my phone',
                subtitle: 'Gemma 4 E4B, offline, private.',
                selected: s.mode == AppMode.local,
                onTap: () => _switchMode(context, viewModel, AppMode.local),
              ),
              _ModeTile(
                label: 'Online (Gemma 4 31B)',
                subtitle: 'Bigger brain via OpenRouter. Needs internet.',
                selected: s.mode == AppMode.online,
                onTap: () => _switchMode(context, viewModel, AppMode.online),
              ),
              if (s.mode == AppMode.online) ...[
                const SizedBox(height: 20),
                _SectionLabel('OpenRouter API key'),
                _KeyField(viewModel: viewModel),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: viewModel.saveApiKey,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: OjaColors.navy, width: 2),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Save',
                            style: OjaText.body(
                                size: 17,
                                weight: FontWeight.w700,
                                color: OjaColors.navy)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: viewModel.testState ==
                                ConnectionTest.running
                            ? null
                            : viewModel.testConnection,
                        style: FilledButton.styleFrom(
                          backgroundColor: OjaColors.navy,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: viewModel.testState == ConnectionTest.running
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: OjaColors.cream,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text('Test',
                                style: OjaText.body(
                                    size: 17,
                                    weight: FontWeight.w700,
                                    color: OjaColors.cream)),
                      ),
                    ),
                  ],
                ),
                if (viewModel.testMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    viewModel.testMessage,
                    style: OjaText.body(
                      size: 15,
                      color: viewModel.testState == ConnectionTest.success
                          ? OjaColors.green
                          : OjaColors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Model: ${s.openRouterModel}',
                  style: OjaText.body(size: 14, color: OjaColors.ink),
                ),
                const SizedBox(height: 20),
                _SectionLabel('Groq API key (fast cloud Whisper)'),
                Text(
                  'Optional. When set, voice transcription runs on Groq '
                  '(sub-second) instead of your phone CPU (5–8 s).',
                  style: OjaText.body(size: 14, color: OjaColors.ink),
                ),
                const SizedBox(height: 8),
                _GroqKeyField(viewModel: viewModel),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: viewModel.saveGroqKey,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: OjaColors.navy, width: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                    ),
                    child: Text('Save Groq key',
                        style: OjaText.body(
                            size: 15,
                            weight: FontWeight.w700,
                            color: OjaColors.navy)),
                  ),
                ),
                if (s.groqApiKey.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('✓ Groq key set — voice will use cloud Whisper.',
                      style: OjaText.body(
                          size: 13, color: OjaColors.green)),
                ],
              ],
              const SizedBox(height: 30),
              _SectionLabel('About'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'OjaAI runs on Gemma 4. In local mode, Gemma 4 E4B listens '
                  'to your voice directly and does everything on your phone. '
                  'In online mode, Whisper transcribes locally and Gemma 4 '
                  '31B on OpenRouter does the reasoning.',
                  style: OjaText.body(size: 15, color: OjaColors.ink),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _switchMode(
  BuildContext context,
  SettingsViewModel viewModel,
  AppMode mode,
) async {
  final navigator = Navigator.of(context);
  final ready = await viewModel.setMode(mode);
  if (!ready) {
    // Setup screen needs to appear — pop everything above the root so
    // _Root re-renders and shows the fresh SetupView.
    navigator.popUntil((route) => route.isFirst);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: OjaText.body(
          size: 13,
          weight: FontWeight.w800,
          color: OjaColors.ink,
        ).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected ? OjaColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? OjaColors.gold : OjaColors.ink,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: OjaText.body(
                          size: 17,
                          weight: FontWeight.w800,
                          color: selected ? OjaColors.cream : OjaColors.navy,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: OjaText.body(
                          size: 14,
                          color:
                              selected ? const Color(0xB3F7F1E3) : OjaColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroqKeyField extends StatefulWidget {
  const _GroqKeyField({required this.viewModel});
  final SettingsViewModel viewModel;

  @override
  State<_GroqKeyField> createState() => _GroqKeyFieldState();
}

class _GroqKeyFieldState extends State<_GroqKeyField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.viewModel.groqKeyDraft);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (v) => widget.viewModel.groqKeyDraft = v,
      obscureText: true,
      style: OjaText.body(size: 16, color: OjaColors.navy),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: widget.viewModel.current.groqApiKey.isNotEmpty
            ? 'gsk_… (saved)'
            : 'gsk_…',
        hintStyle: OjaText.body(size: 15, color: OjaColors.ink),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _KeyField extends StatefulWidget {
  const _KeyField({required this.viewModel});
  final SettingsViewModel viewModel;

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.viewModel.apiKeyDraft);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (v) => widget.viewModel.apiKeyDraft = v,
      obscureText: true,
      style: OjaText.body(size: 16, color: OjaColors.navy),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: widget.viewModel.current.openRouterApiKey.isNotEmpty
            ? 'sk-or-… (saved)'
            : 'sk-or-…',
        hintStyle: OjaText.body(size: 15, color: OjaColors.ink),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
