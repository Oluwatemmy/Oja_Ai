import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/models/agent_result.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ledger_entry.dart';
import '../../domain/models/undoable_action.dart';
import '../../domain/use_cases/calculator.dart';
import '../services/gemma_service.dart';
import '../services/groq_transcriber_service.dart';
import '../services/openrouter_service.dart';
import '../services/settings_service.dart';
import 'ledger_repository.dart';

/// Orchestrates the on-device agent. Two backends behind the same contract:
///   - LOCAL: Gemma 4 E4B on the phone, listens to audio directly.
///   - ONLINE: Whisper transcribes locally, Gemma 4 31B on OpenRouter
///     reasons over text (also handles vision for Snap).
///
/// The tools, staging model, and confirm sheet are identical in both modes.
class AgentRepository {
  AgentRepository({
    required GemmaService gemma,
    required GroqTranscriberService groq,
    required OpenRouterService openRouter,
    required SettingsService settings,
    required LedgerRepository ledger,
  })  : _gemma = gemma,
        _groq = groq,
        _openRouter = openRouter,
        _settings = settings,
        _ledger = ledger;

  final GemmaService _gemma;
  final GroqTranscriberService _groq;
  final OpenRouterService _openRouter;
  final SettingsService _settings;
  final LedgerRepository _ledger;

  /// Online mode uses Groq for cloud transcription. If the Groq key is
  /// missing, returns empty — the caller shows a friendly "set your Groq
  /// key" message instead of failing quietly.
  Future<String> _transcribeOnline(List<Uint8List> wavChunks) async {
    final groqKey = _s.groqApiKey;
    if (groqKey.isEmpty) return '';
    return _groq.transcribe(wavChunks, apiKey: groqKey);
  }

  static const int _maxToolRounds = 8;

  /// Tools that mutate the ledger. Once any of these has run we have
  /// everything we need for the UI (Dart generates the captions
  /// deterministically); no need to spend another HTTP round-trip waiting
  /// for the model to write a summary sentence.
  static const _writeToolNames = {
    'add_records',
    'record_payment',
    'edit_record',
    'delete_record',
  };

  AppSettings get _s => _settings.current;
  bool get _isOnline => _s.mode == AppMode.online;

  // ─── pending-conversation state ─────────────────────────────
  // When the model responds with plain text (usually a clarifying
  // question like "abeg tell me the price"), we keep the chat alive so
  // the next voice recording continues the same conversation instead of
  // starting over.

  InferenceChat? _pendingLocalChat;
  List<OpenRouterMessage>? _pendingOnlineConvo;

  /// Set by the dispatch handlers for delete_record / edit_record; read
  /// (and cleared) by _buildResult so the ViewModel can surface an Undo
  /// snackbar right after the mutation runs.
  UndoableAction? _pendingUndo;

  bool get hasPendingConversation =>
      _pendingLocalChat != null || _pendingOnlineConvo != null;

  Future<void> discardPending() async {
    final local = _pendingLocalChat;
    _pendingLocalChat = null;
    _pendingOnlineConvo = null;
    if (local != null) {
      try {
        await local.session.close();
      } catch (_) {}
    }
  }

  static const String _systemContext = '''
You are OjaAI, the record keeper for a Nigerian market trader. The trader
speaks Nigerian Pidgin or English, often rambling, mixing several records in
one voice note. Money is in naira.

RESPONSE STYLE — CRITICAL: You are an agent, not a chat assistant. NEVER
write "Let me analyse", "Here's the breakdown", "Step 1", numbered lists,
markdown, bullet points, or any explanation of what you are doing. Do NOT
narrate your reasoning. ONLY do these two things: (1) call tools, then
(2) reply with ONE short Pidgin sentence. Nothing else.

Your job:
1. Find every record: sales where money entered ("in") and credit where
   somebody owes the trader ("owe").
2. ALWAYS use the `calculate` tool for any arithmetic (unit price times
   quantity, adding amounts, remaining balance). Never do maths in your head.
3. When somebody has PAID back part or all of a debt, first use
   `search_person` to find the debt, then call `record_payment`.
4. For new records call `add_records` once with every record you found.
5. After all tools succeed, reply with ONE short Pidgin sentence.

NAMES — very important:
Nigerian trading names usually start with a title: Mama, Mummy, Papa, Iya,
Baba, Madam, Oga, Bros, Sister, Aunty, Alhaji, Alhaja, Chief. The title is
PART of the name. Write the person's name EXACTLY as spoken — never drop a
title, never add a title that was not spoken, never swap one title for
another. If no name at all, use "Cash sale".

Key Pidgin phrases and their meaning:
- "she/he don pay am", "e don pay"  → they HAVE paid
- "she/he never pay", "e no pay"    → they have NOT paid
- "dem owe me", "e dey owe me"      → someone owes money

"in" vs "owe" — DEFAULT is "in" (cash sale). Markets run on cash by default;
credit is the exception that a trader always mentions explicitly.
- If the trader does NOT say anything about payment, assume they were paid.
  Type = "in".
- Only use "owe" when the trader EXPLICITLY signals credit: "she never pay",
  "he no pay", "hasn't paid", "on credit", "e dey owe me", "give am credit",
  "she still dey owe", "e never settle".
- Examples:
  - "Mama Alex bought 2 crates of egg, 5400"          → in  (no credit word)
  - "Iya Bola come buy three yam, two thousand"        → in
  - "Bros Sunday take one bag garri, he never pay"     → owe (credit word)
  - "Mummy Delight bought 5000 of goods, she hasn't paid me" → owe

AMOUNT INTERPRETATION — how a trader states prices:
When the trader states ONE money amount alongside a quantity, that is the
TOTAL price for all items, NOT the per-unit price. Do NOT multiply.
- "2 crates of egg, 5400"        → total ₦5,400 (NOT 2 × 5,400)
- "3 bags of rice, 12000"        → total ₦12,000
- "one carton indomie 7000"      → ₦7,000
Only multiply when the trader EXPLICITLY says per-unit: "2 crates at 2700
each", "3 bags at 4000 per bag", "one for one thousand". In those cases, use
the `calculate` tool.

PARTIAL PAYMENT — the most common case, get it right:
When somebody buys for a total price but pays only part, that is EXACTLY TWO
records — the money received ("in") and the balance ("owe"). The TOTAL PRICE
IS NOT A RECORD. Use `calculate` for the balance.
- Example: "Nonso came to buy 6000 naira of rice, he paid me only 4000"
  → calculate("6000 - 4000") = 2000, then add_records with:
    1. {item: "Rice", party: "Nonso", amount: 4000, type: "in"}
    2. {item: "Rice balance", party: "Nonso", amount: 2000, type: "owe"}
The number of records is NOT the number of amounts you heard.

ONLY if you truly heard nothing at all: reply "I no hear any record." Never
say that after calling tools successfully.

EDIT / DELETE — when the trader wants to fix a record:
- "delete Mummy Delight last record" / "remove Mama Alex egg"
  → search_person("Mummy Delight") → delete_record(entry_id)
- "change Mama Alex egg to 5000" / "e no be 5000, na 4500"
  → search_person → edit_record(entry_id, amount: 4500)
- "correct her name to Alhaja Kudi"
  → search_person → edit_record(entry_id, party: "Alhaja Kudi")
Always identify the target record with search_person FIRST. Never edit a
record without an entry_id from a search.

If the trader is ASKING a question about their book instead of recording,
use `get_ledger_summary` / `search_person` and answer in one or two short
Pidgin sentences.
''';

  List<Tool> get _readTools => [
        const Tool(
          name: 'get_ledger_summary',
          description:
              'Get today\'s money-in total, total outstanding debt, and the '
              'list of everybody still owing.',
          parameters: {'type': 'object', 'properties': {}},
        ),
        const Tool(
          name: 'search_person',
          description:
              'Fuzzy-search ledger records by person name. Returns matching '
              'records with entry_id, item, remaining amount and status.',
          parameters: {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': 'The person name to search for',
              },
            },
            'required': ['name'],
          },
        ),
        const Tool(
          name: 'calculate',
          description:
              'Evaluate an arithmetic expression, e.g. "3 * 1800" or '
              '"9000 - 300". Use for ALL maths.',
          parameters: {
            'type': 'object',
            'properties': {
              'expression': {
                'type': 'string',
                'description': 'Arithmetic with + - * / ( ) only',
              },
            },
            'required': ['expression'],
          },
        ),
      ];

  List<Tool> get _writeTools => [
        const Tool(
          name: 'add_records',
          description:
              'Stage new ledger records for the trader to confirm. Call once '
              'with every record found in the voice note or photo.',
          parameters: {
            'type': 'object',
            'properties': {
              'records': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'item': {
                      'type': 'string',
                      'description':
                          'What was sold or taken, e.g. "3 crate egg"',
                    },
                    'party': {
                      'type': 'string',
                      'description':
                          'Who bought or owes, or "Cash sale" if unknown',
                    },
                    'amount': {
                      'type': 'integer',
                      'description': 'Whole naira amount',
                    },
                    'type': {
                      'type': 'string',
                      'enum': ['in', 'owe'],
                      'description':
                          '"in" when money entered, "owe" when person owes',
                    },
                  },
                  'required': ['item', 'party', 'amount', 'type'],
                },
              },
            },
            'required': ['records'],
          },
        ),
        const Tool(
          name: 'record_payment',
          description:
              'Stage a debt repayment. Use entry_id from search_person. '
              'The amount is how much the person paid now.',
          parameters: {
            'type': 'object',
            'properties': {
              'entry_id': {'type': 'string'},
              'amount': {
                'type': 'integer',
                'description': 'Whole naira paid now',
              },
            },
            'required': ['entry_id', 'amount'],
          },
        ),
        const Tool(
          name: 'edit_record',
          description:
              'Change fields of an existing ledger record. Use entry_id '
              'from search_person. Only pass the fields the trader wants '
              'to change; leave the others out.',
          parameters: {
            'type': 'object',
            'properties': {
              'entry_id': {'type': 'string'},
              'item': {'type': 'string'},
              'party': {'type': 'string'},
              'amount': {'type': 'integer'},
              'type': {
                'type': 'string',
                'enum': ['in', 'owe'],
              },
            },
            'required': ['entry_id'],
          },
        ),
        const Tool(
          name: 'delete_record',
          description:
              'Delete an existing ledger record entirely. Use entry_id '
              'from search_person. This also removes any payments linked '
              'to the record.',
          parameters: {
            'type': 'object',
            'properties': {
              'entry_id': {'type': 'string'},
            },
            'required': ['entry_id'],
          },
        ),
      ];

  // ─────────────────────────────────────────────────────────────
  // Public entry points
  // ─────────────────────────────────────────────────────────────

  Future<AgentResult> runVoiceEntry(
    List<Uint8List> wavChunks, {
    bool continueConversation = false,
  }) =>
      _isOnline
          ? _onlineVoice(wavChunks, continueConversation: continueConversation)
          : _localVoice(wavChunks, continueConversation: continueConversation);

  Future<AgentResult> runQuestion(List<Uint8List> wavChunks) =>
      _isOnline ? _onlineQuestion(wavChunks) : _localQuestion(wavChunks);

  Future<AgentResult> runSnapEntry(Uint8List imageBytes) =>
      _isOnline ? _onlineSnap(imageBytes) : _localSnap(imageBytes);

  // ─────────────────────────────────────────────────────────────
  // LOCAL — Gemma 4 E4B, native audio
  // ─────────────────────────────────────────────────────────────

  Future<AgentResult> _localVoice(
    List<Uint8List> wavChunks, {
    bool continueConversation = false,
  }) async {
    final continuing = continueConversation && _pendingLocalChat != null;
    final messages = <Message>[];
    for (var i = 0; i < wavChunks.length; i++) {
      final label = continuing
          ? 'Trader\'s reply:'
          : (wavChunks.length == 1
              ? 'Voice note from the trader:'
              : 'Voice note from the trader, part ${i + 1} of '
                  '${wavChunks.length}:');
      messages.add(Message.withAudio(
        text: label,
        audioBytes: wavChunks[i],
        isUser: true,
      ));
    }
    messages.add(Message.text(
      text: continuing
          ? 'That is my reply. Now record it using the tools and summarise.'
          : 'That is everything. Now record every sale, debt and payment '
              'you heard using the tools, then summarise.',
      isUser: true,
    ));
    return _runLocal(messages, allowWrites: true, continuing: continuing);
  }

  Future<AgentResult> _localQuestion(List<Uint8List> wavChunks) async {
    final messages = <Message>[
      for (var i = 0; i < wavChunks.length; i++)
        Message.withAudio(
          text: 'The trader is asking a question about their ledger:',
          audioBytes: wavChunks[i],
          isUser: true,
        ),
    ];
    return _runLocal(messages, allowWrites: false);
  }

  Future<AgentResult> _localSnap(Uint8List imageBytes) async {
    final messages = [
      Message.withImage(
        text: 'This is a photo of the trader\'s paper ledger book. Read '
            'every line you can see (item, person, amount, whether money '
            'entered or the person owes), then record each line with '
            '`add_records` and summarise.',
        imageBytes: imageBytes,
        isUser: true,
      ),
    ];
    return _runLocal(messages, allowWrites: true);
  }

  Future<AgentResult> _runLocal(
    List<Message> messages, {
    required bool allowWrites,
    bool continuing = false,
  }) async {
    final overallStart = DateTime.now();
    final tools = [..._readTools, if (allowWrites) ..._writeTools];

    final setupStart = DateTime.now();
    final chat = continuing && _pendingLocalChat != null
        ? _pendingLocalChat!
        : await _gemma.createChat(
            tools: tools,
            systemInstruction: _systemContext + _knownCustomersContext(),
            toolChoice: allowWrites ? ToolChoice.required : ToolChoice.auto,
            maxOutputTokens: 256,
          );
    if (!continuing && _pendingLocalChat != null) {
      // A fresh recording implicitly ends any previous conversation.
      final old = _pendingLocalChat!;
      _pendingLocalChat = null;
      try {
        await old.session.close();
      } catch (_) {}
    }
    final chatSetupMs = DateTime.now().difference(setupStart).inMilliseconds;

    final staged = _StagedProposals();
    var answer = '';
    var firstResponseMs = 0;
    var toolRounds = 0;
    var closedChat = false;

    try {
      for (final message in messages) {
        await chat.addQueryChunk(message);
      }
      for (var round = 0; round <= _maxToolRounds; round++) {
        final callStart = DateTime.now();
        final response = await chat.generateChatResponse();
        if (round == 0) {
          firstResponseMs =
              DateTime.now().difference(callStart).inMilliseconds;
        }
        if (response is TextResponse) {
          answer = response.token;
          break;
        }
        final calls = response is ParallelFunctionCallResponse
            ? response.calls
            : response is FunctionCallResponse
                ? [response]
                : const <FunctionCallResponse>[];
        if (calls.isEmpty) break;
        toolRounds++;
        var didWrite = false;
        for (final call in calls) {
          final result = await _dispatch(call.name, call.args, staged,
              allowWrites: allowWrites);
          await chat.addQueryChunk(
            Message.toolResponse(toolName: call.name, response: result),
          );
          if (_writeToolNames.contains(call.name)) didWrite = true;
        }
        // Short-circuit: any write means the UI has what it needs.
        // For read-only "Ask your book" sessions we still let the model
        // finish with a text answer.
        if (allowWrites && didWrite) break;
      }
    } finally {
      final hadStagedResult = staged.entries.isNotEmpty || staged.payments.isNotEmpty;
      if (hadStagedResult || !allowWrites || answer.trim().isEmpty) {
        // Conversation over — either records are staged (trader will
        // confirm) or the model produced nothing useful. Close it.
        try {
          await chat.session.close();
        } catch (_) {}
        _pendingLocalChat = null;
        closedChat = true;
      } else {
        // Text-only response, likely a clarifying question. Keep the
        // chat alive so the trader can just reply.
        _pendingLocalChat = chat;
      }
    }
    // Silence the analyzer — closedChat is intentional bookkeeping.
    // ignore: unused_local_variable
    final _ = closedChat;

    return _buildResult(
      staged: staged,
      answer: answer,
      transcript: '',
      overallStart: overallStart,
      whisperMs: 0,
      chatSetupMs: chatSetupMs,
      firstResponseMs: firstResponseMs,
      toolRounds: toolRounds,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ONLINE — Whisper transcribes; Gemma 4 31B on OpenRouter reasons
  // ─────────────────────────────────────────────────────────────

  Future<AgentResult> _onlineVoice(
    List<Uint8List> wavChunks, {
    bool continueConversation = false,
  }) async {
    final overallStart = DateTime.now();
    final whisperStart = DateTime.now();
    final transcript = await _transcribeOnline(wavChunks);
    final whisperMs = DateTime.now().difference(whisperStart).inMilliseconds;
    if (transcript.trim().isEmpty) {
      return AgentResult(
        answer: _s.groqApiKey.isEmpty
            ? 'No Groq key. Set am for settings to use online mode.'
            : 'I no hear any record.',
        timing: AgentTiming(
          whisperMs: whisperMs,
          chatSetupMs: 0,
          firstResponseMs: 0,
          totalMs: DateTime.now().difference(overallStart).inMilliseconds,
          toolRounds: 0,
        ),
        transcript: transcript,
      );
    }
    final continuing =
        continueConversation && _pendingOnlineConvo != null;
    final userMessage = continuing
        ? OpenRouterMessage.user('TRADER\'S REPLY:\n"$transcript"\n\n'
            'Now record it using the tools and summarise.')
        : OpenRouterMessage.user('TRANSCRIPT of the trader\'s voice note:\n'
            '"$transcript"\n\nNow record every sale, debt and payment using '
            'the tools, then summarise.');
    final baseMessages = continuing
        ? [..._pendingOnlineConvo!, userMessage]
        : [
            OpenRouterMessage.system(
                _systemContext + _knownCustomersContext()),
            userMessage,
          ];
    if (!continuing) _pendingOnlineConvo = null;
    return _runOnline(
      baseMessages,
      allowWrites: true,
      transcript: transcript,
      whisperMs: whisperMs,
      overallStart: overallStart,
      continuing: continuing,
    );
  }

  Future<AgentResult> _onlineQuestion(List<Uint8List> wavChunks) async {
    final overallStart = DateTime.now();
    final whisperStart = DateTime.now();
    final transcript = await _transcribeOnline(wavChunks);
    final whisperMs = DateTime.now().difference(whisperStart).inMilliseconds;
    if (transcript.trim().isEmpty) {
      return AgentResult(
        answer: _s.groqApiKey.isEmpty
            ? 'No Groq key. Set am for settings to use online mode.'
            : 'I no hear anything. Try ask am again.',
        timing: AgentTiming(
          whisperMs: whisperMs,
          chatSetupMs: 0,
          firstResponseMs: 0,
          totalMs: DateTime.now().difference(overallStart).inMilliseconds,
          toolRounds: 0,
        ),
        transcript: transcript,
      );
    }
    return _runOnline(
      [
        OpenRouterMessage.system(_systemContext + _knownCustomersContext()),
        OpenRouterMessage.user(
            'The trader is asking a question about their ledger:\n'
            '"$transcript"'),
      ],
      allowWrites: false,
      transcript: transcript,
      whisperMs: whisperMs,
      overallStart: overallStart,
    );
  }

  Future<AgentResult> _onlineSnap(Uint8List imageBytes) async {
    final overallStart = DateTime.now();
    return _runOnline(
      [
        OpenRouterMessage.system(_systemContext + _knownCustomersContext()),
        OpenRouterMessage.userWithImage(
          text: 'This is a photo of the trader\'s paper ledger book. Read '
              'every line you can see and record each line with `add_records` '
              'then summarise.',
          imageBase64: base64Encode(imageBytes),
        ),
      ],
      allowWrites: true,
      transcript: '',
      whisperMs: 0,
      overallStart: overallStart,
    );
  }

  /// OpenRouter tool schema — OpenAI's `type: function` wrapper around ours.
  List<Map<String, dynamic>> _openRouterTools({required bool allowWrites}) {
    final tools = [..._readTools, if (allowWrites) ..._writeTools];
    return [
      for (final t in tools)
        {
          'type': 'function',
          'function': {
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
          },
        },
    ];
  }

  Future<AgentResult> _runOnline(
    List<OpenRouterMessage> messages, {
    required bool allowWrites,
    required String transcript,
    required int whisperMs,
    required DateTime overallStart,
    bool continuing = false,
  }) async {
    final tools = _openRouterTools(allowWrites: allowWrites);
    final settings = _s;
    if (settings.openRouterApiKey.isEmpty) {
      return AgentResult(
        answer: 'Abeg set your OpenRouter API key for settings.',
        transcript: transcript,
        timing: AgentTiming(
          whisperMs: whisperMs,
          chatSetupMs: 0,
          firstResponseMs: 0,
          totalMs: DateTime.now().difference(overallStart).inMilliseconds,
          toolRounds: 0,
        ),
      );
    }
    final staged = _StagedProposals();
    var answer = '';
    var firstResponseMs = 0;
    var toolRounds = 0;

    final convo = List<OpenRouterMessage>.from(messages);
    try {
      for (var round = 0; round <= _maxToolRounds; round++) {
        final callStart = DateTime.now();
        final response = await _openRouter.chat(
          apiKey: settings.openRouterApiKey,
          model: settings.openRouterModel,
          messages: convo,
          tools: tools,
          toolChoice:
              allowWrites && round == 0 ? 'required' : 'auto',
          maxTokens: 512,
        );
        if (round == 0) {
          firstResponseMs =
              DateTime.now().difference(callStart).inMilliseconds;
        }
        if (!response.hasToolCalls) {
          answer = response.text;
          break;
        }
        toolRounds++;
        // Append the assistant's tool calls to the convo, then a `tool`
        // message per result so the model sees results on the next round.
        convo.add(OpenRouterMessage.assistantToolCalls(response.toolCalls));
        var didWrite = false;
        for (final call in response.toolCalls) {
          final result = await _dispatch(call.name, call.arguments, staged,
              allowWrites: allowWrites);
          convo.add(OpenRouterMessage.tool(
            toolCallId: call.id,
            name: call.name,
            content: jsonEncode(result),
          ));
          if (_writeToolNames.contains(call.name)) didWrite = true;
        }
        // Skip the next HTTP round-trip once we have staged mutations.
        // Saves ~3–5s per voice entry on the online path.
        if (allowWrites && didWrite) break;
      }
    } on OpenRouterException catch (e) {
      final friendly = e.isAuth
          ? 'API key no valid. Check am for settings.'
          : e.isRateLimit
              ? 'OpenRouter say slow down small. Try again.'
              : 'Online no work: ${e.message}';
      return AgentResult(
        answer: friendly,
        transcript: transcript,
        timing: AgentTiming(
          whisperMs: whisperMs,
          chatSetupMs: 0,
          firstResponseMs: firstResponseMs,
          totalMs: DateTime.now().difference(overallStart).inMilliseconds,
          toolRounds: toolRounds,
        ),
      );
    }

    // Track pending online convo: keep alive on text-only replies so a
    // follow-up voice message can continue the same thread.
    final hadStagedResult =
        staged.entries.isNotEmpty || staged.payments.isNotEmpty;
    if (allowWrites && !hadStagedResult && answer.trim().isNotEmpty) {
      _pendingOnlineConvo = [
        ...convo,
        OpenRouterMessage(role: 'assistant', content: answer),
      ];
    } else {
      _pendingOnlineConvo = null;
    }

    return _buildResult(
      staged: staged,
      answer: answer,
      transcript: transcript,
      overallStart: overallStart,
      whisperMs: whisperMs,
      chatSetupMs: 0,
      firstResponseMs: firstResponseMs,
      toolRounds: toolRounds,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Shared plumbing
  // ─────────────────────────────────────────────────────────────

  AgentResult _buildResult({
    required _StagedProposals staged,
    required String answer,
    required String transcript,
    required DateTime overallStart,
    required int whisperMs,
    required int chatSetupMs,
    required int firstResponseMs,
    required int toolRounds,
  }) {
    final totalMs = DateTime.now().difference(overallStart).inMilliseconds;
    final timing = AgentTiming(
      whisperMs: whisperMs,
      chatSetupMs: chatSetupMs,
      firstResponseMs: firstResponseMs,
      totalMs: totalMs,
      toolRounds: toolRounds,
    );
    final undo = _pendingUndo;
    _pendingUndo = null;
    return AgentResult(
      entries: staged.entries
          .map((e) => e.withCaption(_entryCaption(e)))
          .toList(),
      payments: staged.payments
          .map((p) => p.withCaption(_paymentCaption(p)))
          .toList(),
      answer: answer.trim(),
      timing: timing,
      transcript: transcript,
      undoable: undo,
    );
  }

  String _knownCustomersContext() {
    final seen = <String>{};
    for (final entry in _ledger.entries) {
      final party = entry.party.trim();
      if (party.isEmpty || party.toLowerCase() == 'cash sale') continue;
      seen.add(party);
      if (seen.length >= 30) break;
    }
    if (seen.isEmpty) return '';
    return '\nKNOWN CUSTOMERS (exact ledger spellings): ${seen.join(', ')}.\n'
        'Use this list ONLY to correct clear mis-hearings of the SAME full '
        'name. Never expand a shorter spoken name into a longer known one. '
        'Trust what the trader said.\n';
  }

  static String _entryCaption(EntryProposal e) => e.type == EntryType.moneyIn
      ? 'I hear say ${e.party} buy ${e.item} — ₦${_fmt(e.amount)} don enta.'
      : 'I hear say ${e.party} carry ${e.item} — e dey owe ₦${_fmt(e.amount)}.';

  static String _paymentCaption(PaymentProposal p) =>
      'I hear say ${p.party} don pay ₦${_fmt(p.amount)} for ${p.item}. '
      'E remain ₦${_fmt(p.remainingAfter)}.';

  static String _fmt(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  Future<Map<String, dynamic>> _dispatch(
    String name,
    Map<String, dynamic> args,
    _StagedProposals staged, {
    required bool allowWrites,
  }) async {
    try {
      switch (name) {
        case 'get_ledger_summary':
          return _ledgerSummary();
        case 'search_person':
          return _searchPerson(args['name'] as String? ?? '');
        case 'calculate':
          final expression = args['expression'] as String? ?? '';
          final value = Calculator.evaluate(expression);
          return {
            'result': value == value.roundToDouble() ? value.round() : value,
          };
        case 'add_records':
          if (!allowWrites) return {'error': 'read-only session'};
          return _stageRecords(args['records'], staged);
        case 'record_payment':
          if (!allowWrites) return {'error': 'read-only session'};
          return _stagePayment(args, staged);
        case 'edit_record':
          if (!allowWrites) return {'error': 'read-only session'};
          return _editRecord(args);
        case 'delete_record':
          if (!allowWrites) return {'error': 'read-only session'};
          return _deleteRecord(args);
        default:
          return {'error': 'Unknown tool $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _ledgerSummary() async {
    final totals = _ledger.totals;
    final debts = await _ledger.outstandingDebts();
    return {
      'today_money_in': totals.todayIn,
      'total_outstanding_debt': totals.totalOwed,
      'people_owing': [
        for (final d in debts)
          {
            'entry_id': d.id,
            'party': d.party,
            'item': d.item,
            'remaining': d.amount,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _searchPerson(String name) async {
    if (name.trim().isEmpty) return {'matches': []};
    var matches = await _ledger.searchByParty(name.trim());
    if (matches.isEmpty) {
      for (final word in name.trim().split(RegExp(r'\s+'))) {
        if (word.length < 3) continue;
        matches = await _ledger.searchByParty(word);
        if (matches.isNotEmpty) break;
      }
    }
    return {
      'matches': [
        for (final m in matches.take(6))
          {
            'entry_id': m.id,
            'party': m.party,
            'item': m.item,
            'type': m.type.code,
            'remaining': m.amount,
            'settled': m.settled,
          },
      ],
    };
  }

  Map<String, dynamic> _stageRecords(
    Object? rawRecords,
    _StagedProposals staged,
  ) {
    if (rawRecords is! List) return {'error': 'records must be a list'};
    var count = 0;
    for (final raw in rawRecords) {
      if (raw is! Map) continue;
      final record = Map<String, dynamic>.from(raw);
      final amount = _asInt(record['amount']);
      final item = (record['item'] as String?)?.trim() ?? '';
      if (amount == null || amount <= 0 || item.isEmpty) continue;
      staged.entries.add(EntryProposal(
        item: item,
        party: (record['party'] as String?)?.trim().isNotEmpty == true
            ? (record['party'] as String).trim()
            : 'Cash sale',
        amount: amount,
        type: record['type'] == 'owe' ? EntryType.owe : EntryType.moneyIn,
      ));
      count++;
    }
    if (count == 0) return {'error': 'no valid records in the list'};
    return {'status': 'staged for trader confirmation', 'count': count};
  }

  Future<Map<String, dynamic>> _stagePayment(
    Map<String, dynamic> args,
    _StagedProposals staged,
  ) async {
    final entryId = args['entry_id'] as String? ?? '';
    final amount = _asInt(args['amount']);
    if (amount == null || amount <= 0) {
      return {'error': 'amount must be a positive whole-naira number'};
    }
    final entry = await _ledger.entryById(entryId);
    if (entry == null || entry.type != EntryType.owe) {
      return {
        'error': 'No debt found with entry_id "$entryId". '
            'Use search_person first.',
      };
    }
    staged.payments.add(PaymentProposal(
      entryId: entry.id,
      party: entry.party,
      item: entry.item,
      amount: amount,
      outstanding: entry.amount,
    ));
    return {
      'status': 'staged for trader confirmation',
      'party': entry.party,
      'outstanding_before': entry.amount,
      'remaining_after': (entry.amount - amount).clamp(0, entry.amount),
    };
  }

  Future<Map<String, dynamic>> _editRecord(Map<String, dynamic> args) async {
    final entryId = args['entry_id'] as String? ?? '';
    if (entryId.isEmpty) {
      return {'error': 'entry_id required — use search_person first'};
    }
    final existing = await _ledger.entryById(entryId);
    if (existing == null) return {'error': 'No record with that entry_id'};

    final rawType = args['type'] as String?;
    final updated = await _ledger.editEntry(
      entryId,
      item: args['item'] as String?,
      party: args['party'] as String?,
      amount: _asInt(args['amount']),
      type: rawType == 'in'
          ? EntryType.moneyIn
          : rawType == 'owe'
              ? EntryType.owe
              : null,
    );
    if (updated == null) return {'error': 'Update failed'};
    _pendingUndo = EditedEntryAction(
      description: 'Edited ${existing.party} — ${existing.item}',
      previous: existing,
    );
    return {
      'status': 'edited',
      'party': updated.party,
      'item': updated.item,
      'amount': updated.amount,
      'type': updated.type.code,
    };
  }

  Future<Map<String, dynamic>> _deleteRecord(
      Map<String, dynamic> args) async {
    final entryId = args['entry_id'] as String? ?? '';
    if (entryId.isEmpty) {
      return {'error': 'entry_id required — use search_person first'};
    }
    final existing = await _ledger.entryById(entryId);
    if (existing == null) {
      return {'error': 'No record with that entry_id'};
    }
    // Capture cascade targets BEFORE the delete so undo can restore them.
    final linked = await _ledger.entriesLinkedTo(entryId);
    await _ledger.deleteEntry(entryId);
    _pendingUndo = DeletedEntryAction(
      description: 'Deleted ${existing.party} — ${existing.item}',
      entry: existing,
      linkedPayments: linked,
    );
    return {
      'status': 'deleted',
      'party': existing.party,
      'item': existing.item,
    };
  }

  /// Reverse a voice-driven delete or edit. Called by the UI when the
  /// trader taps "Undo" on the snackbar.
  Future<void> undo(UndoableAction action) async {
    switch (action) {
      case DeletedEntryAction(:final entry, :final linkedPayments):
        await _ledger.restoreEntry(entry, linkedPayments);
      case EditedEntryAction(:final previous):
        await _ledger.replaceEntry(previous);
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value.replaceAll(',', ''));
    return null;
  }
}

class _StagedProposals {
  final List<EntryProposal> entries = [];
  final List<PaymentProposal> payments = [];
}
