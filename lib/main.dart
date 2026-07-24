import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/agent_repository.dart';
import 'data/repositories/ledger_repository.dart';
import 'data/services/audio_recorder_service.dart';
import 'data/services/database_service.dart';
import 'data/services/gemma_service.dart';
import 'data/services/groq_transcriber_service.dart';
import 'data/services/openrouter_service.dart';
import 'data/services/settings_service.dart';
import 'data/services/tts_service.dart';
import 'ui/core/theme.dart';
import 'ui/features/home/view_models/home_view_model.dart';
import 'ui/features/ledger/view_models/ledger_view_model.dart';
import 'ui/features/settings/view_models/settings_view_model.dart';
import 'ui/features/setup/view_models/setup_view_model.dart';
import 'ui/features/setup/views/setup_view.dart';
import 'ui/features/shell/views/app_shell.dart';
import 'ui/features/snap/view_models/snap_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OjaApp());
}

class OjaApp extends StatelessWidget {
  const OjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Services
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => GemmaService()),
        Provider(
          create: (_) => GroqTranscriberService(),
          dispose: (_, GroqTranscriberService s) => s.dispose(),
        ),
        Provider(
          create: (_) => OpenRouterService(),
          dispose: (_, OpenRouterService s) => s.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        Provider(
          create: (_) => AudioRecorderService(),
          dispose: (_, AudioRecorderService s) => s.dispose(),
        ),
        Provider(create: (_) => TtsService()),
        // Repositories
        ChangeNotifierProvider(
          create: (context) =>
              LedgerRepository(database: context.read<DatabaseService>())
                ..load(),
        ),
        Provider(
          create: (context) => AgentRepository(
            gemma: context.read<GemmaService>(),
            groq: context.read<GroqTranscriberService>(),
            openRouter: context.read<OpenRouterService>(),
            settings: context.read<SettingsService>(),
            ledger: context.read<LedgerRepository>(),
          ),
        ),
        // ViewModels
        ChangeNotifierProvider(
          create: (context) => SetupViewModel(
            gemma: context.read<GemmaService>(),
            settings: context.read<SettingsService>(),
            openRouter: context.read<OpenRouterService>(),
          )..start(),
        ),
        ChangeNotifierProvider(
          create: (context) => SettingsViewModel(
            settings: context.read<SettingsService>(),
            openRouter: context.read<OpenRouterService>(),
            setup: context.read<SetupViewModel>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => HomeViewModel(
            agent: context.read<AgentRepository>(),
            ledger: context.read<LedgerRepository>(),
            recorder: context.read<AudioRecorderService>(),
            tts: context.read<TtsService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => LedgerViewModel(
            agent: context.read<AgentRepository>(),
            ledger: context.read<LedgerRepository>(),
            recorder: context.read<AudioRecorderService>(),
            tts: context.read<TtsService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => SnapViewModel(
            agent: context.read<AgentRepository>(),
            ledger: context.read<LedgerRepository>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'OjaAI',
        debugShowCheckedModeBanner: false,
        theme: buildOjaTheme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupViewModel>();
    if (setup.phase == SetupPhase.ready) return const AppShell();
    return SetupView(viewModel: setup);
  }
}
