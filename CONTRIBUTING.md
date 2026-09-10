# Contributing

```bash
./build.sh      # builds build/EasySpeech.app
./package.sh    # builds the distributable DMG
```

No package manager, no dependencies to fetch. Xcode 26+ command line tools and macOS 26.

To distribute a signed build, set your identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

## Layout

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
│   ├── UpdateChecker.swift      GitHub release discovery
│   ├── Updater.swift            Download, verify, swap, relaunch
│   └── JobQueue.swift           Sequential batch processing
├── Export/       SRT / VTT / text writers, number repair
└── Views/        SwiftUI interface

EasySpeechArt/    Icon set — .icns, .iconset, menu bar template, SVG masters
Packaging/        DMG background generator
```

## Things that will bite you

**The analyzer's audio format is Int16, not Float32.** `SpeechAnalyzer.bestAvailableAudioFormat`
returns 16 kHz mono **Int16**. Reaching for `AVAudioPCMBuffer.floatChannelData` gets you `nil`,
every buffer is silently dropped, and the run "succeeds" instantly with an empty transcript and no
error. `AudioSource` reads the format's `streamDescription` and copies raw bytes, so it survives
Apple changing this.

**Audio is pulled, not pushed.** An `AsyncStream` buffers without bound, and decoding runs far
ahead of recognition — a 3.6-hour podcast decodes in about 12 seconds and parks ~405 MB of PCM.
`AudioSource.InputSequence` is a pull-based `AsyncSequence` that decodes inside `next()`, so the
analyzer draws one buffer at a time and memory stays flat. This took peak memory from 405 MB to
20 MB and was slightly *faster*.

**Progress must come from results, not from decoding.** Decode position hits 100% in seconds while
recognition still has minutes to run. `FileTranscriber` reports progress from finalized result
ranges instead.

**Apple's inverse text normalization is very literal.** Spoken "millions" comes back as the digit
string `1000000s`, "twenty million" as `20000000`, "first" as `1st`. `SpokenNumbers` repairs the
unambiguous cases. Read its rules before adding more: years, phone numbers, prices, percentages and
dates must stay untouched, and it runs on every word of every transcript, so it bails early on text
containing no digits.

**Contextual strings currently do nothing.** `AnalysisContext.contextualStrings` is
supplied with the user's corrected spellings and the analyzer demonstrably retains them —
`setContext` succeeds and the values read back — but on the macOS 26 builds tested the
recognizer produces byte-identical output with and without them. They're still passed in
case that changes. `VocabularyCorrector` is what actually fixes names today, and it is
deliberately exact rather than fuzzy: an edit-distance version fixed the real mis-hearings
but also rewrote "The weather institute" into a listed name and swallowed the word "with".
For captioning, a confident wrong correction is worse than a missed one.

**The app binary is also the CLI.** `CommandLineRunner.shouldHandle` decides, and treats
*any* real argument as a command line invocation. It deliberately does not check `isatty`:
scripts, CI and Shortcuts all pipe their output, and launching a GUI there hangs the
caller. Launch Services delivers documents by Apple event, never argv, so a file path in
argv can only have come from a shell.

**A watched folder can be silently unreadable.** macOS gates Desktop, Documents, Downloads
and iCloud Drive behind TCC, and a denied directory read looks exactly like an empty
folder. `FolderWatcher` probes readability up front and surfaces the reason.

## Updates

`Updater` downloads the release DMG, verifies it, swaps the bundle and relaunches.

**Why an update doesn't re-trigger Gatekeeper.** macOS attaches `com.apple.quarantine` only to what
a browser or Mail downloads. `URLSession` doesn't, and the app doesn't opt in via
`LSFileQuarantineEnabled`, so a self-fetched update arrives unquarantined and simply launches. The
user never repeats the Privacy & Security approval. The installer strips the attribute anyway, in
case that ever changes.

**What's verified before installing.** There's no Developer ID to pin against, so the checks are
layered: HTTPS to a repository compiled into the binary rather than a preference; the SHA-256
GitHub publishes for the asset, recomputed over the download; the unpacked bundle must identify as
`com.easyspeech.ui`; and `codesign --verify --deep` must pass. Any failure discards the download.

**Two traps, both only reachable by pressing the button.** Don't clean up the staging directory in
`install()` — the swap runs in a detached script that waits for the app to exit, so the cleanup
wins the race and the swap finds nothing to copy. And AppKit **vetoes `NSApp.terminate` while a
sheet is presented** (a plain Quit returns `-128`), so the sheet is dismissed first and the script
escalates wait → `TERM` → `KILL`. Because that can force-quit, updating is refused while a
transcription is running.

## Packaging

The DMG background is generated by `Packaging/MakeDMGBackground.swift` as a HiDPI TIFF rather than
checked in as a binary. Window layout is written by driving Finder over AppleScript — the only
thing that can put icon positions and a background picture into a `.DS_Store`. If Finder refuses,
packaging still succeeds and produces a plain image.

The scratch image is built under a temp directory on purpose: Finder records the backing image's
path inside the volume's `.DS_Store`, and that file ships to everyone who downloads the DMG.
Building it inside the repo would publish the maintainer's home directory. `package.sh` refuses to
ship an image that contains local paths.

## Accuracy

Cross-checked against an independent `whisper.cpp` (`medium.en`) transcript of the same 3 hour 38
minute recording: **89.2% word-level agreement**, word counts 0.4% apart, runs of 116 consecutive
identical words, full timeline coverage with zero gaps over 20 seconds, and no hallucination loops
in either. Two independent engines landing that close is good evidence neither is drifting.
