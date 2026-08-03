# Dictator

Dictator is a small native macOS menu-bar app for hold-to-talk dictation. Hold the
global shortcut, speak, and release — Dictator transcribes with OpenAI
`gpt-transcribe`, then pastes into the focused field (or copies to the clipboard
with a toast if nothing is focused).

## Requirements

- macOS 14 or newer
- An OpenAI API key
- Xcode Command Line Tools

## Setup

1. Copy `.env.example` to `.env` and set `OPENAI_API_KEY`, or paste the key in the app Settings.
2. Build and run:

```sh
make run
```

3. Grant **Microphone** and **Accessibility** when prompted (also available in the app window).

Default shortcut: **⌃⌥D** (Control+Option+D). Hold to record, release to stop.

## Build

```sh
make build   # writes build/Dictator.app
make install # copies to ~/Applications
```

## Notes

- The API key is stored in the Keychain after first use.
- If a `.env` file is present at build time, it is bundled for first-launch seeding.
- History of recent transcriptions is kept locally (last 50).
