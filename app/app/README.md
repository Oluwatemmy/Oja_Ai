# OjaAI

Talk your market, we go write am. A fully offline, on-device AI ledger for
Nigerian market traders — powered by **Gemma 4 E2B** running on the phone.

## What it does

- **Talk** — press the mic and ramble: *"Madam Ngozi buy 3 crate egg, five
  thousand four hundred. Iya Risi carry 2 wrapper, nine thousand, she never
  pay."* Gemma listens to the raw audio (native audio modality — no separate
  speech-to-text), works out every record, uses the calculator tool for the
  maths, and stages each record for a one-tap "Correct" confirmation.
- **Payments by voice** — *"Sister Bola don pay 300 from di sewing money"* —
  Gemma fuzzy-finds the debt with the `search_person` tool and stages the
  payment.
- **Snap** — photograph a page of the paper ledger book; Gemma vision reads
  each line into records.
- **Ledger** — colour-coded book (green = money enta, red = dem owe), tick a
  debt paid by hand, and "Ask your book anything" by voice (*"How much I make
  dis week?"*).
- **Speaks back** in Nigerian Pidgin via the OS text-to-speech.

Everything — audio understanding, reasoning, tool calling, structured output —
happens inside Gemma **on the phone**. After the one-time model download the
app never needs the internet.

## Architecture

MVVM with a strict layer split (see `lib/`):

```
lib/
├── data/
│   ├── repositories/   # LedgerRepository (source of truth), AgentRepository (agent loop)
│   └── services/       # GemmaService, AudioRecorderService, DatabaseService, TtsService
├── domain/
│   ├── models/         # LedgerEntry, EntryProposal, PaymentProposal, AgentResult
│   └── use_cases/      # Calculator (safe arithmetic for the model's tool)
└── ui/
    ├── core/           # theme (design tokens), confirm sheet, mic widgets
    └── features/       # home (talk), ledger, snap, setup — each views/ + view_models/
```

### The agent loop

`AgentRepository` gives Gemma five tools:

| Tool | Kind | Purpose |
|---|---|---|
| `get_ledger_summary` | read | totals + everybody still owing |
| `search_person` | read | fuzzy name match ("Mama Ngozi" ≈ "Madam Ngozi") |
| `calculate` | read | ALL arithmetic (LLMs can't be trusted with maths) |
| `add_records` | write | stage new sale/debt records |
| `record_payment` | write | stage a repayment against a found debt |

Write tools only **stage** proposals — nothing touches the database until the
trader taps **Correct** on the receipt sheet.

### Audio pipeline

`record` captures 16 kHz mono PCM16 (Gemma's native audio format). Long voice
notes are split at the quietest moment near each 28 s boundary (Gemma's audio
encoder takes clips up to 30 s) and fed as sequential audio messages in one
conversation, so Gemma hears everything.

## Model

- **Gemma 4 E2B** `.litertlm` (~2.4 GB), int4, text + vision + audio, native
  function-calling tokens. Runs on ~4 GB-RAM phones via LiteRT-LM.
- Downloaded on first launch from
  `litert-community/gemma-4-E2B-it-litert-lm` on Hugging Face.
- Gated model? Pass a token at build time:
  `flutter build apk --dart-define=HUGGINGFACE_TOKEN=hf_...`

## Build

```sh
flutter pub get
flutter test
flutter build apk --debug
```

Requires a **physical device** for audio/vision inference (simulators are not
supported by the LiteRT-LM runtime).
