<div align="center">

# OjaAI

### Talk your market — we go write am.

**A voice-first, offline-first ledger for Nigerian market traders.**
The trader talks in Pidgin. Gemma 4 hears the raw audio, reasons, calls tools,
and writes the book.

`Flutter` · `Gemma 4 E4B` · `LiteRT-LM` · `on-device audio + vision + tool calling`

</div>

---

## Table of contents

- [The problem](#the-problem)
- [What the app can do](#what-the-app-can-do)
- [Screen by screen](#screen-by-screen)
- [Two runtime modes](#two-runtime-modes)
- [Architecture](#architecture)
- [The agent loop](#the-agent-loop)
- [Prompt engineering](#prompt-engineering-that-earned-its-place)
- [Voice pipeline](#voice-pipeline)
- [The accounting invariant](#the-accounting-invariant)
- [Data model](#data-model)
- [Model & configuration](#model--configuration)
- [Build](#build)
- [Tests](#tests)
- [Pitfalls we already paid for](#pitfalls-we-already-paid-for)
- [Known limitations](#known-limitations)
- [Design system](#design-system)

---

## The problem

A trader in Balogun market sells forty things before noon. Half cash, half
credit. The record is a paper book written between customers — or not written
at all. By evening nobody remembers whether Iya Risi paid for the wrapper.

Typing that into an app is **worse** than the paper book. Nobody stops a sale
to fill a form, pick a dropdown, and tap Save.

**So OjaAI removes the form.** The trader talks the way they already talk —
rambling, mixing five records into one breath, in Pidgin — and the ledger
writes itself. One tap confirms it.

---

## What the app can do

Every example below is a single voice note. Nothing is typed.

### 1. Record a cash sale

> 🎙️ *"Mama Alex bought 2 crate egg, five thousand four hundred."*

Gemma hears the audio → calls `add_records` → the receipt sheet slides up:

```
I hear say Mama Alex buy 2 crate egg — ₦5,400 don enta.
                                    [ Correct ]  [ Try again ]
```

One tap and it's in the book. Note it did **not** multiply 2 × 5,400 — one
amount beside a quantity is the total, and the prompt teaches that explicitly.

### 2. Record credit

> 🎙️ *"Iya Risi carry 2 wrapper, nine thousand, she never pay."*

*"She never pay"* is an explicit credit signal → the record is staged as
`owe`, in red, and the amount joins **Dem owe** rather than **Today enta**.

Without a credit phrase, the default is a cash sale. Markets run on cash;
credit is the exception a trader always says out loud.

### 3. Partial payment — two records from one sentence

> 🎙️ *"Nonso came to buy 6000 naira of rice, he paid me only 4000."*

The model calls `calculate("6000 - 4000")` — it is never allowed to do
arithmetic in its head — then stages **exactly two** records:

| Item | Party | Amount | Type |
|---|---|---|---|
| Rice | Nonso | ₦4,000 | `in` |
| Rice balance | Nonso | ₦2,000 | `owe` |

The ₦6,000 total is *not* a record. The number of records is not the number
of amounts you heard.

### 4. Pay down an existing debt

> 🎙️ *"Sister Bola don pay 300 from di sewing money."*

`search_person("Sister Bola")` fuzzy-matches the open debt → `record_payment`
stages it with the balance:

```
I hear say Sister Bola don pay ₦300 for sewing.
E remain ₦8,700.
```

Confirming reduces the debt **and** inserts a linked money-in row, so the cash
shows up in today's takings. (See [the accounting invariant](#the-accounting-invariant).)

### 5. Fix a mistake by voice

> 🎙️ *"E no be 5000, na 4500"* · *"Delete Mama Alex last record"* ·
> *"Correct her name to Alhaja Kudi"*

`search_person` finds the row, then `edit_record` / `delete_record` commits
straight away with an **Undo** snackbar. Deleting a debt cascades to its linked
payment rows — and undo restores every one of them.

### 6. Ask your book anything

> 🎙️ *"How much I make today?"* · *"Who still dey owe me?"*

Read-only session — write tools are stripped from the tool list entirely, so
a question can never mutate the ledger. Gemma answers in one or two short
Pidgin sentences and speaks it aloud.

### 7. Snap the old paper book

📸 Photograph a page of the paper ledger. Gemma's vision encoder reads every
line — item, person, amount, paid or owing — and stages each one through the
same confirm sheet. Migrating a whole book is a handful of photos.

### 8. Multi-turn clarification

> 🎙️ *"Mama Chidi carry three yam."*
> 🤖 *"Abeg, how much be di price?"*

When the model replies with text instead of calling tools, the chat session is
held open. The mic turns gold and the label becomes **"Press am, reply"** —
the next recording continues the same conversation instead of starting over.

---

## Screen by screen

| Screen | What it does |
|---|---|
| **Setup** | First launch: pick **local** or **online**. Local → download Gemma with live progress. Online → paste OpenRouter + Groq keys (validated with a real test call). Escape hatch at the bottom of each: *"← Use online mode instead"*. |
| **Talk** (home) | The mic. Idle → listening (gold pulse + live waveform) → thinking → confirm sheet. Auto-stops after 2.5 s of silence. Shows Today enta / Dem owe totals. |
| **Snap** | Full-bleed camera on a dark surface. Shutter → Gemma vision → confirm queue → drops you into Ledger. Hidden automatically when the loaded model has no vision encoder. |
| **Ledger** | The book. Green = money enta, red = dem owe, red margin rule down the page. Tick a debt paid by hand, tap a row to edit it in a sheet, or hold the mic to ask a question. |
| **Customer profile** | Every record for one party, with their running balance. |
| **Settings** | Switch mode live, manage both API keys, change the online model. Switching to a mode that isn't ready drops you back to Setup. |

### The confirm sheet

Receipt-styled bottom sheet with a zigzag torn-top edge. It shows:

- the staged record in plain Pidgin, captioned **deterministically in Dart**
  (never by the model — they hallucinate captions);
- the raw transcript in an italic quote box, so the trader sees exactly what
  was heard;
- a timing line — `Total 4.1s · Whisper 0.6s · Gemma 3.5s (2 tool rounds)`;
- **Correct** / **Try again**, plus *"Skip only dis one →"* when several
  records are queued from one voice note.

---

## Two runtime modes

The tool schemas, staging model, and confirm sheet are **identical** in both.
Only the reasoning backend changes.

| | **Local** (default) | **Online** |
|---|---|---|
| Audio | Gemma hears WAV natively — no ASR step | Groq `whisper-large-v3-turbo` |
| Reasoning | Gemma 4 E4B on the phone | `google/gemma-4-31b-it` via OpenRouter |
| Vision | Gemma 4 vision encoder | Same model, base64 image |
| Network | **None, ever** | Required |
| Cost | Free | Your API keys |
| Setup | ~4.3 GB one-time download | Paste two keys |
| Needs | 8 GB+ RAM phone | Any phone |

Local mode is the point of the product. Online mode exists for phones that
can't hold a 4 GB model in RAM, and as a quality ceiling to measure the
on-device path against.

---

## Architecture

MVVM with strict layering. Views never touch services; ViewModels never touch
the database. `Provider` wires the graph in [`lib/main.dart`](lib/main.dart).

```
lib/
├── main.dart                          # DI graph: services → repositories → view models
├── data/
│   ├── repositories/
│   │   ├── ledger_repository.dart     # Source of truth over sqflite. Commit, edit,
│   │   │                              # delete, undo, the payment invariant.
│   │   └── agent_repository.dart      # The agent loop. Both backends, one contract.
│   └── services/
│       ├── gemma_service.dart         # Only file that touches the flutter_gemma API
│       ├── openrouter_service.dart    # OpenAI-compatible client + retry/backoff
│       ├── groq_transcriber_service.dart  # multipart POST to Groq Whisper
│       ├── audio_recorder_service.dart # 16 kHz PCM16 capture, VAD, smart chunking
│       ├── wav_codec.dart             # raw PCM → WAV header
│       ├── database_service.dart      # sqflite CRUD, one `entries` table
│       ├── settings_service.dart      # ChangeNotifier over the platform keystore
│       └── tts_service.dart           # flutter_tts wrapper
├── domain/
│   ├── models/
│   │   ├── ledger_entry.dart          # LedgerEntry, EntryType, LedgerTotals
│   │   ├── agent_result.dart          # AgentResult, EntryProposal, PaymentProposal, AgentTiming
│   │   ├── undoable_action.dart       # sealed: DeletedEntryAction | EditedEntryAction
│   │   └── app_settings.dart          # AppMode, AppSettings
│   └── use_cases/
│       └── calculator.dart            # shunting-yard evaluator — no eval(), no identifiers
└── ui/
    ├── core/
    │   ├── theme.dart                 # OjaColors, OjaText, formatNaira
    │   └── widgets/                   # mic_widgets, confirm_models, confirm_sheet
    └── features/                      # setup · settings · shell · home · ledger ·
                                       # snap · customer — each views/ + view_models/
```

**Dependency injection** (`main.dart`): eight services → two repositories →
five view models. `LedgerRepository` and `SettingsService` are `ChangeNotifier`s,
so Home totals and the Ledger list re-render on every mutation without manual
refresh calls.

---

## The agent loop

`AgentRepository` registers **seven tools** with identical JSON schemas in both
modes (wrapped in OpenAI's `type: function` envelope for OpenRouter).

### Read tools — always available

| Tool | Purpose |
|---|---|
| `get_ledger_summary()` | Today's money-in, total outstanding, everybody still owing |
| `search_person(name)` | Fuzzy party match; falls back to per-word search on a miss |
| `calculate(expression)` | **All** arithmetic. `+ - * / ( )` only, evaluated in Dart |

### Write tools — voice-entry and Snap runs only

| Tool | Commits how? |
|---|---|
| `add_records([{item, party, amount, type}])` | **Staged** → confirm sheet |
| `record_payment(entry_id, amount)` | **Staged** → confirm sheet |
| `edit_record(entry_id, item?, party?, amount?, type?)` | Direct + Undo snackbar |
| `delete_record(entry_id)` | Direct + Undo snackbar (cascades to linked payments) |

### Loop mechanics

- **Max 8 tool rounds**, then the loop exits.
- **`ToolChoice.required` on the first turn** of a voice-entry run, so a small
  model can't essay its way out of calling a tool. `auto` for "Ask your book".
- **Short-circuit on write.** Once any write tool has run, the loop breaks
  immediately — Dart already generates the captions deterministically, so
  waiting for the model's closing sentence buys nothing. Saves ~3–5 s per entry
  on the online path.
- **Read-only enforcement is structural.** Question flows never register write
  tools, and `_dispatch` refuses them again with `{'error': 'read-only session'}`.
- **Nothing reaches the database without a tap** for `add_records` /
  `record_payment`. A model that mishears cannot corrupt the book — enforced at
  the repository layer, not in the prompt.

---

## Prompt engineering that earned its place

Every rule below traces to a specific failure on real Pidgin voice notes.

1. **Response style, in caps.** *"You are an agent, not a chat assistant. NEVER
   write 'Let me analyse', 'Here's the breakdown', 'Step 1', numbered lists,
   markdown, bullet points. ONLY (1) call tools, then (2) reply with ONE short
   Pidgin sentence."* Small models ramble unless you spell this out.

2. **Titles are part of the name.** Mama, Mummy, Papa, Iya, Baba, Madam, Oga,
   Bros, Sister, Aunty, Alhaji, Alhaja, Chief — never dropped, never added,
   never swapped. No name at all → `"Cash sale"`.

3. **`in` vs `owe` defaults to `in`.** Only explicit credit language
   (*"she never pay"*, *"e dey owe me"*, *"on credit"*) produces a debt.
   *"Bought"* alone is not credit.

4. **One amount beside a quantity is the total.** *"2 crates of egg, 5400"* →
   ₦5,400. Multiply only on explicit *"each"* / *"per bag"* / *"one for X"* —
   and then via the `calculate` tool.

5. **Partial payment is exactly two records**, with the total price excluded,
   stated as *"the number of records is NOT the number of amounts you heard."*

6. **A Pidgin phrase dictionary** is embedded in the prompt — *"she don pay am"*
   → paid, *"she never pay"* → not paid — rather than trusting inference.

7. **Silence handling.** *"I no hear any record"* is permitted only when nothing
   was heard **and** no tool succeeded. Never after successful tools.

8. **Known-customer biasing.** Up to 30 existing party names are injected, with
   an explicit guard: correct clear mis-hearings of the *same full name*, but
   never expand a shorter spoken name into a longer known one.

### Whisper bias prompt (online mode)

Groq gets an `initial_prompt` priming it for the same vocabulary — Nigerian
name titles, naira, and Pidgin phrases to expect verbatim — which is what keeps
*"she don pay am"* from being transcribed as *"she done pay them"*.

---

## Voice pipeline

Capture is identical in both modes: **16 kHz mono PCM16** — the exact format
Gemma's audio encoder expects, so nothing is ever resampled.

- **Voice activity detection.** RMS ≥ 0.02 counts as speech; 2.5 s of trailing
  silence fires `endOfUtterance` so the trader never hunts for a stop button.
  If no speech was heard at all, the agent is skipped entirely.
- **Chunking at the quietest moment.** Gemma's encoder takes clips up to 30 s.
  Long notes split near each 28 s boundary at the quietest 200 ms window in the
  preceding 6 s — so a cut never lands mid-word — and are fed as sequential
  audio messages inside one conversation.
- **Hard cap of 180 s** so a forgotten mic can't eat RAM (~5.5 MB at 3 min).
- **Live amplitude stream** drives the waveform bars in the UI.

**Local:** WAV → `Message.withAudio()` → Gemma's USM audio encoder → agent loop.

**Online:** WAV → multipart POST to Groq (`whisper-large-v3-turbo`, `language=en`,
Pidgin `initial_prompt`) → transcript → OpenRouter chat completions with the same
tools → same loop. Chat calls are wrapped in retry-with-backoff (3 attempts,
400 ms / 800 ms) because OpenRouter drops connections mid-stream on Vertex hiccups.

---

## The accounting invariant

**A repayment is two movements, never one.** When a debt is paid — by voice or
by ticking the checkbox:

1. the `owe` row's amount goes **down** (and flips to `settled` when it hits 0);
2. a **linked** money-in row is inserted — `"Payment — {item}"` with
   `linked_to = <debt id>` — so the cash the trader physically received counts
   in **Today enta**.

Reversing is symmetrical: un-ticking a settled debt deletes every payment row
linked to it and restores the outstanding amount. Deleting a debt cascades to
its linked payments, so a partially-paid debt never leaves orphaned
`"Payment — X"` rows floating in today's takings.

This is the single most load-bearing rule in the app. It is covered by tests.

---

## Data model

```dart
enum EntryType { moneyIn, owe }   // stored as 'in' / 'owe'

class LedgerEntry {
  final String id;
  final String item;
  final String party;        // "Cash sale" when unknown
  final int amount;          // whole naira — no floats, ever
  final EntryType type;
  final DateTime createdAt;
  final bool settled;
  final String? linkedTo;    // payment row → the debt it pays down
}
```

SQLite schema (v2, with a live migration from v1):

```sql
CREATE TABLE entries(
  id         TEXT PRIMARY KEY,
  item       TEXT NOT NULL,
  party      TEXT NOT NULL,
  amount     INTEGER NOT NULL,
  type       TEXT NOT NULL,            -- 'in' | 'owe'
  created_at INTEGER NOT NULL,
  settled    INTEGER NOT NULL DEFAULT 0,
  linked_to  TEXT
);
```

`Today enta` sums `type='in'` since local midnight. `Dem owe` sums
`type='owe' AND settled=0` across all time.

---

## Model & configuration

- **Gemma 4 E4B** `.litertlm`, int4 — text + vision + audio with native
  `<|tool_call>` tokens. ~4.3 GB on disk, ~5.5 GB resident with the USM audio
  encoder, vision tower and KV cache.
- Runs on **LiteRT-LM** with the GPU backend preferred (Adreno/Mali via OpenCL),
  falling back to CPU automatically when OpenCL is unavailable.
- Downloaded on first launch through a real foreground service, so Android
  doesn't kill a 4 GB transfer when the app is backgrounded.
  HuggingFace's CDN supports HTTP Range, so `background_downloader` resumes
  automatically after a network drop.

### Build-time configuration

All compile-time, via `--dart-define`:

| Define | Default | Purpose |
|---|---|---|
| `OJA_MODEL_URL` | Gemma 4 E4B on HF | Which `.litertlm` to fetch |
| `OJA_MODEL_TYPE` | `gemma4` | `gemma4` \| `qwen3` \| `gemmaIt` — tool-call token format |
| `OJA_MAX_TOKENS` | `2048` | Context window (must be ≥ 1024) |
| `HUGGINGFACE_TOKEN` | *(empty)* | **Required** — the Gemma repos are gated |
| `OPENROUTER_KEY` | *(empty)* | Bootstrapped into secure storage on first launch |
| `GROQ_API_KEY` | *(empty)* | Same — lets a demo APK ship with keys baked in |

API keys live in `flutter_secure_storage` (Android `EncryptedSharedPreferences`).
Compile-time keys are written into the keystore once on first launch, then read
from there — never re-baked, never in `shared_preferences`.

**Trading down to E2B** (2.4 GB, for ~6 GB-RAM phones):

```sh
--dart-define=OJA_MODEL_URL=https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
```

---

## Build

### Verified toolchain

| | Version |
|---|---|
| Flutter | 3.44.8 stable (Dart 3.12.2) |
| JDK | 17 (`C:\tools\java\jdk-17.0.19+10`) |
| Android SDK | Build-Tools 35 |
| Gradle / AGP / Kotlin | 8.12 · 8.9.1 · 2.1.0 |

### Windows (PowerShell)

```powershell
$env:JAVA_HOME = "C:\tools\java\jdk-17.0.19+10"
$env:ANDROID_SDK_ROOT = "C:\tools\android-sdk"
$env:PATH = "C:\tools\flutter\bin;$env:JAVA_HOME\bin;$env:PATH"

flutter pub get
flutter analyze
flutter test

# Release APK (universal, ~154 MB)
flutter build apk --release --dart-define=HUGGINGFACE_TOKEN=hf_xxxxx

# Per-ABI — what you actually ship for sideloading (~120 MB arm64-v8a)
flutter build apk --release --split-per-abi `
  --dart-define=HUGGINGFACE_TOKEN=hf_xxxxx `
  --dart-define=GROQ_API_KEY=gsk_xxxxx `
  --dart-define=OPENROUTER_KEY=sk-or-xxxxx
```

Output lands in `build/app/outputs/flutter-apk/`. A cold release build takes
**10–15 minutes** — most of it packaging MediaPipe/LiteRT native libraries.

> If a build dies with *"Timeout waiting to lock build logic queue"*, a stale
> Gradle daemon is holding `android/.gradle/*.lock`. Stop the daemons
> (`./gradlew --stop`, or kill the `java.exe` processes) and rebuild.

**A physical device is required.** LiteRT-LM does not support simulators, and
audio/vision inference needs real hardware.

### Android specifics

- `largeHeap="true"` — the model does not fit a default heap.
- `SystemForegroundService` merged with `foregroundServiceType="dataSync"`;
  without it the model download crashes on API 34+.
- `libOpenCL.so` / `-car` / `-pixel` declared as optional native libraries for
  the GPU delegate.
- Permissions: `INTERNET`, `RECORD_AUDIO`, `CAMERA`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`.

---

## Tests

```sh
flutter test
```

- **`calculator_test.dart`** — operator precedence, unary minus, thousands
  separators, malformed input.
- **`ledger_repository_test.dart`** — commit entry, commit payment, partial and
  full settlement, tick / un-tick reversal, linked-payment cascade delete,
  undo/restore, party search.

Both run against `sqflite_common_ffi` with `inMemoryDatabasePath`, so no device
or emulator is needed.

---

## Pitfalls we already paid for

Documented so nobody re-learns them at 2 a.m.

| Pitfall | Consequence |
|---|---|
| **Gemma 3 1B cannot reliably call tools** | It rambles instead of emitting calls. Gemma 4's native `<\|tool_call>` tokens are the whole reason the agent works. |
| **`ToolChoice.required` is only real on Gemma 4** | On Gemma 3 the plugin prompt-injects it and the model can simply ignore it. |
| **`whisper_ggml` on Android is CPU-only** (`use_gpu = false`) | 30 s per short clip, plus ~80 MB of bundled FFmpeg per ABI. Dropped entirely in favour of Groq. |
| **Gemma 3 and 4 are gated on HuggingFace** | Needs an HF token *with the license accepted*, at **build** time — it is a compile-time constant. |
| **OpenRouter drops connections mid-stream** | Vertex hiccups. Always wrap chat calls in retry-with-backoff. |
| **4 GB-RAM phones OOM on Gemma 4 E4B** | Killed during model load. Online mode works fine on the same hardware. |
| **Never let the model write the confirmation caption** | They hallucinate. Captions are string-built in Dart from the staged proposal. |

---

## Known limitations

- **Release builds are debug-signed.** `android/app/build.gradle.kts` still uses
  the Flutter template's `signingConfigs.getByName("debug")`. Fine for
  sideloading; the Play Store will reject it.
- **`HandshakeException` bypasses the retry logic.** `OpenRouterService._withRetry`
  catches `SocketException`, `TimeoutException` and `http.ClientException` — a TLS
  handshake failure is none of those, so it propagates on the first attempt with
  no backoff and surfaces raw to the user.
- **Connection errors read as bad keys.** `testConnection` swallows every
  exception and returns `false`, so a network failure while saving keys is
  reported as *"OpenRouter key no work."*
- **The universal APK is ~154 MB** — MediaPipe/LiteRT natives for every ABI.
  Use `--split-per-abi` or an app bundle.
- **No automatic E2B fallback.** A phone that can't hold E4B gets a RAM-specific
  error message, but must switch models by rebuilding with `OJA_MODEL_URL`.
- **Android only.** iOS would work but is out of scope.

---

## Design system

Tokens in [`lib/ui/core/theme.dart`](lib/ui/core/theme.dart) — a paper ledger
rendered in software.

| Token | Hex | Use |
|---|---|---|
| Cream | `#F7F1E3` | Page background |
| Paper | `#EDE7D6` | Ruled lines, cards |
| Navy | `#1C2B4A` | Ink, headings, mic circle |
| Gold | `#D9A441` | Listening pulse, primary action |
| Green | `#2F7D5E` | Money enta |
| Red | `#B5442E` | Dem owe, margin rule |
| Ink | `#3A3A3A` | Body copy |

Type: **Caveat** for the handwritten logo, **Manrope** for money numbers,
**Karla** for body copy.

Signature details: the red margin rule running down the ledger page, the
zigzag torn-top edge on the receipt sheet, and the gold pulse that only
appears while the mic is actually hearing you.
