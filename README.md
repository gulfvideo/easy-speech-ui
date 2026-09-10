# EasySpeech

<img src="EasySpeechArt/EasySpeech-1024.png" alt="EasySpeech" width="120" />

A fast, native macOS transcription app built entirely on **Apple's on-device Speech framework**. No Whisper, no models to download and manage, no FFmpeg, no Electron.

It's a rebuild of [EasyWhisperUI](https://github.com/mehtabmahir/easy-whisper-ui) — same job, same workflow, different engine.

---

## Why

EasyWhisperUI is a great app, but its architecture carries weight: an Electron runtime, a compiled `whisper.cpp` binary, a bundled FFmpeg, and multi-gigabyte GGML models you download and pick between. On macOS 26, Apple ships `SpeechAnalyzer` / `SpeechTranscriber` — an on-device recognizer with no length limit, real word-level timestamps, and models the OS manages and shares with Dictation.

That removes most of the moving parts:

| | EasyWhisperUI | EasySpeech |
|---|---|---|
| Runtime | Electron (~200 MB) | Native Swift (~1 MB) |
| Engine | whisper.cpp + Metal | Apple SpeechAnalyzer (Neural Engine) |
| Models | You download & choose (75 MB – 3 GB) | OS-managed, shared with Dictation |
| Audio conversion | FFmpeg → temp WAV on disk | AVFoundation, in-process, no temp file |
| Startup | Electron boot | Instant |
| Languages | ~100 | 45 |
| Translation | Built into the model | Apple Translation framework |

The honest trade-off is at the bottom of that table: **fewer languages**, and translation is a separate step. If you transcribe Icelandic, stay on Whisper. If you work in the 45 supported languages, this is faster, lighter, and better integrated.

---

## Features

Everything EasyWhisperUI does, minus the parts Apple makes unnecessary:

- **Batch queue** — drop in a pile of files, processed one at a time
- **Live transcription** from the microphone, with in-progress text shown greyed until finalized
- **Menu bar dictation** — start from the status item, talk, stop, and the text is already on your clipboard
- **Output formats** — `.txt`, `.srt`, `.vtt`
- **Real word-level timestamps**, so subtitle cues are cut at natural pauses and balanced across two lines
- **Readable numbers** — Apple's recognizer emits "1000000s of people" and "a 1000 years old"; EasySpeech repairs those to "millions of people" and "a thousand years old" without touching years, phone numbers or ordinary counts
- **Light, dark, or system appearance**
- **Translation** to 20+ languages, on-device, with timestamps preserved
- **Drag & drop** anywhere in the window, onto the Dock icon, or via Finder's *Open With*
- **Automatic format handling** — mp3, m4a, wav, aiff, flac, mp4, mov and more, no conversion step
- **Optional FFmpeg fallback** for `.ogg`, `.opus`, `.mkv`, `.wma`
- **Language models download on demand**, or pre-download them in Settings

### Mac things it does properly

- Full menu bar with real shortcuts — ⌘O open, ⌘R start, ⌘. stop, ⇧⌘L live, ⇧⌘E export
- Toolbar holds actions only; settings live in the Options inspector, and Language is also in the Transcribe menu so it's reachable with the inspector closed
- Contextual menus on every row; ⌫ removes a file
- Rows are draggable back out to the Finder
- Copy as plain text, with timestamps, or as SRT
- Window size, sidebar width, inspector state and all options persist
- Live transcription is a separate window, so it can sit beside a running batch
- A status item that reports live progress ("Transcribing 31% — 1 left") and keeps the app running when every window is closed, the way a menu bar utility should. Turn it off in Settings and the app quits with its last window instead.
- Full-text search inside a transcript
- **Never overwrites** an existing file — appends " 2" the way the Finder does

---

## Performance

Measured on this machine (Apple Silicon, macOS 26) against a **3 hour 38 minute** podcast MP3 — 13,114 seconds of two-host conversational speech:

| | Result |
|---|---|
| Wall clock | **167 seconds** |
| Speed | **78× realtime** |
| CPU time | 20s user / 2.6s system |
| Peak memory | **20.5 MB** |
| Output | 4,590 segments · 39,665 words · 210 KB text |

The gap between 167 seconds of wall clock and 20 seconds of CPU is the point: the Neural Engine does the recognition, so the machine stays responsive and cool while a batch runs.

Memory is flat regardless of length — a 3.6-hour file and a 30-second file both sit around 20 MB, because audio is pulled on demand rather than decoded up front.

---

## Requirements

- **macOS 26 or later** (this is where `SpeechAnalyzer` was introduced)
- Apple Silicon recommended
- Xcode 26+ command line tools to build

---

## Install

Download **`EasySpeech-1.0.0-macOS-arm64.dmg`** from the
[latest release](https://github.com/gulfvideo/easy-speech-ui/releases/latest),
open it, and drag EasySpeech to Applications. It's a 1.2 MB download.

### First launch: macOS will block it

EasySpeech isn't signed with an Apple Developer ID, so macOS will refuse to open it the
first time with a message like *"Apple could not verify EasySpeech is free of malware."*
This is expected for any independently distributed app that hasn't paid Apple's $99/yr
developer fee — it is not a judgement about this app. To get past it:

1. Try to open EasySpeech once, and let it be blocked.
2. Open **System Settings › Privacy & Security**.
3. Scroll down to the message about EasySpeech and click **Open Anyway**.
4. Confirm.

You only do this once.

> On macOS 15 and later, right-clicking and choosing *Open* no longer bypasses this —
> the Privacy & Security route above is the one that works.

Prefer the terminal? This does the same thing:

```bash
xattr -dr com.apple.quarantine /Applications/EasySpeech.app
```

### If you'd rather not trust a stranger's binary

Fair. The whole app is ~2,900 lines of Swift with no dependencies — read it and build it
yourself in about a minute:

```bash
git clone https://github.com/gulfvideo/easy-speech-ui.git
cd easy-speech-ui
./build.sh
open build/EasySpeech.app
```

A locally built copy is signed with your own machine's ad-hoc signature and never
quarantined, so none of the above applies.

---

## Build

```bash
./build.sh
open build/EasySpeech.app
```

That's the whole process — no package manager, no dependencies to fetch. To install:

```bash
cp -R build/EasySpeech.app /Applications/
```

To build the distributable disk image:

```bash
./package.sh
```

The build script ad-hoc signs the app so the microphone permission prompt works. To distribute it, set your signing identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

---

## Project layout

```
Sources/EasySpeech/
├── App/          @main entry, AppDelegate, menu commands
├── Models/       Transcript, Job, AppSettings
├── Engine/
│   ├── AudioSource.swift        AVFoundation decode → PCM (pull-based)
│   ├── FileTranscriber.swift    SpeechAnalyzer orchestration
│   ├── LiveTranscriber.swift    Microphone capture
│   ├── LocaleCatalog.swift      Language model install/reserve
│   ├── TranslationService.swift Apple Translation framework
│   └── JobQueue.swift           Sequential batch processing
├── Export/       SRT / VTT / text writers
└── Views/        SwiftUI interface

EasySpeechArt/     Icon set — .icns, .iconset, menu bar template, SVG masters
```

### Accuracy

Checked against EasyWhisperUI (whisper.cpp, `medium.en`) on the same 3 hour 38 minute
podcast — two completely independent engines on hard, fast, overlapping radio talk:

| | Result |
|---|---|
| Word count | 39,821 vs 39,661 — **0.4% apart** |
| Word-level agreement | **89.2%** |
| Longest verbatim agreement | 116 consecutive identical words |
| Timeline coverage | first cue 0.0s, last ends 13,113.1s of 13,114s |
| Gaps over 20s | **0** |
| Hallucination loops | none in either (Apple had slightly fewer) |

Where they disagree it's mostly proper nouns and genuinely unclear audio, and the two
trade wins about evenly. One consistent stylistic difference: Apple normalizes to formal
English ("going to"), Whisper stays verbatim ("gonna").

### Three things worth knowing if you hack on this

**The analyzer's audio format is Int16, not Float32.** `SpeechAnalyzer.bestAvailableAudioFormat` returns 16 kHz mono **Int16**. Reaching for `AVAudioPCMBuffer.floatChannelData` gets you `nil` and a silently empty transcript. `AudioSource` reads the format's `streamDescription` and copies raw bytes, so it keeps working if Apple changes it.

**Apple's inverse text normalization is very literal.** Spoken "millions" comes back as
the digit string `1000000s`, "twenty million" as `20000000`, "a thousand years old" as
`a 1000 years old`. `SpokenNumbers` repairs the unambiguous cases; see its rules before
adding more, because years, phone numbers, prices and percentages must stay untouched.

**Audio is pulled, not pushed.** An `AsyncStream` buffers without bound, and decoding runs far ahead of recognition — a 3.6-hour podcast decodes in about 12 seconds and parks ~405 MB of PCM in memory. `AudioSource.InputSequence` is a pull-based `AsyncSequence` that decodes inside `next()`, so the analyzer draws one buffer at a time and memory stays flat no matter how long the file is.

---

## Known limits

- **45 languages**, not Whisper's ~100. Settings › Languages lists them.
- **No custom models.** Apple manages the acoustic model; there is no `tiny`/`large-v3` choice and no way to load your own. If you need a specific Whisper model, use EasyWhisperUI.
- **No `--arguments` box.** Nothing to pass them to.
- **Punctuation is always on.** Apple gives no toggle, so the app doesn't pretend to offer one.
- **Translation quality** is Apple's, not Whisper's — generally good for major languages, weaker for rare pairs.

---

## License

MIT — see [LICENSE](LICENSE).

Credit to [mehtabmahir/easy-whisper-ui](https://github.com/mehtabmahir/easy-whisper-ui) for the original app and its interaction design.
