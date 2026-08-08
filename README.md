# Ramblr

Ramblr is a native macOS menu-bar app for hold-to-talk dictation. Hold the
global shortcut, speak, and release — Ramblr transcribes with OpenAI
`gpt-transcribe`, then pastes into the focused field (or copies to the clipboard
with a toast if nothing is focused).

Compose mode holds a second shortcut, rewrites the transcript into a professional
but casual email body with `gpt-5.6-luna`, and pastes the result.

## Requirements

- macOS 14 or newer
- An OpenAI API key
- Xcode Command Line Tools

## Setup

1. Copy `.env.example` to `.env` and set `OPENAI_API_KEY`, or paste the key in Settings → Artificial Intelligence.
2. Build and run:

```sh
make run
```

3. Grant **Microphone**, **Input Monitoring**, and **Accessibility** when prompted (also available in Settings → Permissions).

Default shortcuts:
- **Dictation:** Fn + ⌃ (hold to record, release to paste)
- **Compose:** Fn + ⌃ + C (hold to record, release to paste an email)

## Build

```sh
make build   # writes build/Ramblr.app
make install # copies build/Ramblr.app to /Applications
```

You can also drag `build/Ramblr.app` into `/Applications` in Finder.

## Notes

- The API key is stored in the Keychain after first use.
- If a `.env` file is present at build time, it is bundled for first-launch seeding.
- History of recent transcriptions is kept locally (last 50).
- The UI is dark mode only.
