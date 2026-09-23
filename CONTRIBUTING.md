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
├── App/          @main entry (app or CLI), AppDelegate, menu commands
├── CLI/          Headless transcription for scripts and Shortcuts
├── Models/       Transcript, Job, Correction, AppSettings
├── Engine/
│   ├── AudioSource.swift            AVFoundation decode → PCM (pull-based)
│   ├── FileTranscriber.swift        SpeechAnalyzer orchestration
│   ├── LiveTranscriber.swift        Microphone capture
│   ├── LocaleCatalog.swift          Language model install/reserve
│   ├── AnalysisContextFactory.swift Contextual strings for recognition
│   ├── TranslationService.swift     Apple Translation framework
│   ├── FolderWatcher.swift          Watched-folder intake
│   ├── TranscriptPlayer.swift       Click-a-line playback
│   ├── UpdateChecker.swift          GitHub release discovery
│   ├── Updater.swift                Download, verify, swap, relaunch
│   └── JobQueue.swift               Batch processing, 1-6 files at once
├── Export/       SRT / VTT / text writers, number repair, corrections
└── Views/        SwiftUI interface

EasySpeechArt/    Icon set — .icns, .iconset, menu bar template, SVG masters
Packaging/        DMG background generator
```

## Things that will bite you

**Ordinary audio must not go through `AVAssetReader`.** Every `AVAssetReader` audio decode
starts a CoreMedia pipeline with its own `coremedia.audioqueue`, `readerOfflineMixer` and
`audiomentor` threads. One is fine. Six at once — the batch concurrency cap — deadlocked inside
AudioToolbox's AudioQueue XPC bridge after nineteen hours of continuous work: *"dispatch_sync
called on queue already owned by current thread"*, with no app frames anywhere on the crashing
stack. That is a framework bug and cannot be fixed here, only avoided.

`AudioSource.InputSequence.Iterator` therefore tries `AVAudioFile` first, which reads through
ExtAudioFile and brings up no pipeline at all, and falls back to `AVAssetReader` only for video
containers `AVAudioFile` cannot open. Measured on the same 14-minute MP3: the asset-reader path
spawns those three thread families, the audio-file path spawns none and decodes in 0.42s.

Switching decoders changes chunk boundaries, which changes recognition slightly — 99.6% word
agreement on a 3,359-word episode, with identical first and last cue timestamps, so no audio is
lost. Preflight asserts the audio path spawns zero `coremedia.audioqueue` threads.

**Never clamp an `@Observable` property inside its own `didSet`.** Writing
`x = clamp(x)` in `didSet` is a normal idiom for a stored property — Swift suppresses the
re-entry. The `@Observable` macro rewrites the stored property into a computed one, and that
suppression is gone: the assignment calls the setter, which runs `didSet`, which assigns again,
until the stack guard page is hit. It shipped in 1.2.6 as `concurrentJobs` and crashed the app
every time the setting was changed — 74,546 frames deep.

It is invisible from the call site, compiles clean, passes the linter, and survives any test that
only ever *reads* the property. Clamp where the value is read instead (`init`, and the point of
use). `build.sh` now refuses to build if any property assigns to itself inside its own `didSet`;
that check exists because nothing else catches this.

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

## Before every release

```bash
./Tests/preflight.sh          # everything that must pass
./Tests/preflight.sh --quick  # same, minus the concurrency stage
```

`package.sh` runs it and refuses to build a DMG if it fails, so shipping without it means
deliberately setting `SKIP_PREFLIGHT=1`. It covers, in order: the build (including the
self-assigning-`didSet` guard), the in-process `--self-test`, a real transcription of speech
generated with `say(1)` whose words must come back, per-format skipping, four kinds of malformed
input, six concurrent transcriptions completing, the version being newer than the last tag, and
finally a check that no crash report was written while any of that ran.

`EasySpeech --self-test` is the in-process half and runs in under a second. It is deliberately
biased towards *doing* rather than inspecting, because both crashes this project has shipped were
in code the tests of the day never executed:

- It **writes** every setting, including out-of-range values, rather than reading them. This is
  the check that catches the `@Observable` `didSet` trap above — reinstate that bug and the
  self-test dies with signal 11.
- It drives the queue through claim, reorder, pause and cancel rather than asserting on a
  freshly-built one.

If you add a setting, add it to `settingsSurviveBeingWritten`. A setting that is never written by
the suite is a setting with no coverage, and that is exactly how 1.2.6 shipped.

The end-to-end fixture is generated with `say`, not checked in — no binary blobs in the repo, and
because the spoken text is known the transcript can be checked for the actual words. A run that
"succeeds" with an empty transcript is a real failure mode here (see the Int16 note above) and it
exits 0, so asserting on content rather than exit status is the point.

## Soak testing

Before a release, run the engine over real long-form material rather than clips. The last
pass covered 24 hours of audio across 15 files in one process: 954 seconds, 90× realtime,
peak 39 MB, no failures. Repeating a single clip 25 times drifted 0.5 MB, which is the
check that matters for leaks. Also worth re-testing: mid-flight cancellation, a file
deleted while it's being read, silence, a video with no audio track, and a file whose
extension lies about its contents. Each of those has produced a bug at least once.

## Accuracy

Cross-checked against an independent `whisper.cpp` (`medium.en`) transcript of the same 3 hour 38
minute recording: **89.2% word-level agreement**, word counts 0.4% apart, runs of 116 consecutive
identical words, full timeline coverage with zero gaps over 20 seconds, and no hallucination loops
in either. Two independent engines landing that close is good evidence neither is drifting.

## Batch concurrency

`JobQueue` runs `AppSettings.concurrentJobs` files at once through a task group with a
concurrency cap. The queue is `@MainActor`, which is what makes it safe: `claimNextQueued()`
takes a job and marks it `.preparing` in the same main-actor step, so two workers can never
pull the same file. Main-actor isolation does not serialise the work itself — each
`process(_:)` suspends at its first `await` and the real transcription happens off the actor,
which is why several can be in flight at once.

The cap of 6 is measured, not arbitrary. On an M5 Pro over 30-minute files:

```
1 at a time   72× realtime      4   207×
2             121×              6   255×
                                8   248×   ← past the knee
```

One stream does not saturate the Neural Engine — at concurrency 1 the whole app sits at
roughly 35% of a single core on an 18-core machine. Raising it trades per-file latency for
batch throughput. Past 6 the curve turns over, so the setting stops there.

The limit is read once when a run starts, so changing it mid-batch applies to the next run.

`pause()` sets a flag that makes `claimNextQueued()` return nil; files already running finish
and are written out, because `SpeechAnalyzer` has no way to suspend a stream and stopping one
would throw the work away. The drain deliberately stays alive while paused (polling every
200 ms) rather than exiting — otherwise Resume races the wind-down and the queue can stall
with work still in it.

The slot check happens *before* claiming a job, not after. Claiming first marks one extra file
`.preparing` while it waits for a slot, which both miscounts the active files and lets one more
start after a pause.
