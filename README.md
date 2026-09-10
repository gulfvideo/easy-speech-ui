# EasySpeech

<img src="EasySpeechArt/EasySpeech-1024.png" alt="EasySpeech" width="110" />

Fast, native macOS transcription powered entirely by **Apple's on-device Speech framework**.

No cloud, no API keys, no models to download and manage, no Python, no Electron, no FFmpeg. Audio never leaves your Mac. The whole app is a 2 MB download with zero dependencies.

![EasySpeech](docs/screenshot.png)

---

## Features

- **Batch queue** — drop in a pile of files, processed one at a time
- **Live transcription** from the microphone, and **menu bar dictation**: start from the status item, talk, stop, and the text is on your clipboard
- **`.txt`, `.srt` and `.vtt`** output, with real word-level timestamps so subtitle cues break at natural pauses
- **Translation** to 20+ languages, on-device, timestamps preserved
- **Audio *or* video** — mp3, m4a, wav, aiff, flac and mp4, mov, m4v. Drop a recording straight in; EasySpeech reads the audio track itself, so there's no converting to MP3 first
- **Watched folder** — point it at a folder and anything dropped there is transcribed on its own
- **Corrections** — tell it "you hear *Ensure if I*, it's *Ensurify*" once and every transcript is fixed from then on
- **Click any line to hear it** — a play control on each line cues the original audio to that moment, for checking a name before captions ship
- **Command line tool** for scripting and Shortcuts
- **Automatic updates** that don't make you repeat the macOS security approval
- Drag & drop, Finder *Open With*, full menu bar and keyboard shortcuts, light/dark/system appearance
- Never overwrites an existing file

## Performance

**24 hours of podcasts and sermons — 15 files — transcribed in 954 seconds.** That's **90× realtime**, with peak memory of **39 MB** and no failures.

The Neural Engine does the recognition, so the machine stays responsive throughout. Memory is flat regardless of length: it plateaus after the third file and stays there, and repeating one clip 25 times in a single run drifted half a megabyte.

## Requirements

**macOS 26 or later** on Apple Silicon. `SpeechAnalyzer` doesn't exist before macOS 26.

---

## Install

Download the DMG from the [latest release](https://github.com/gulfvideo/easy-speech-ui/releases/latest) and drag EasySpeech onto Applications.

![Installing from the disk image](docs/dmg-install.png)

### First launch is blocked by macOS

EasySpeech isn't signed with an Apple Developer ID, so macOS refuses to open it the first time. This is expected for any independently distributed app that hasn't paid Apple's $99/yr developer fee.

1. Try to open EasySpeech once, and let it be blocked.
2. Open **System Settings › Privacy & Security**.
3. Scroll to the message about EasySpeech and click **Open Anyway**.

You only do this once — updates never ask again. On macOS 15+, right-click → *Open* no longer works for this; the Privacy & Security route does.

Prefer to build it yourself? It's ~4,700 lines of Swift with no dependencies:

```bash
git clone https://github.com/gulfvideo/easy-speech-ui.git
cd easy-speech-ui && ./build.sh && open build/EasySpeech.app
```

A locally built copy is never quarantined, so none of the above applies.

### Corrections

Recognition errors cluster on names the model has no reason to expect. Add the ones you
hit and they're fixed in every transcript from then on.

![Correction rules](docs/corrections.png)

## Command line

The app binary doubles as a CLI, so one build serves both:

```bash
alias easyspeech=/Applications/EasySpeech.app/Contents/MacOS/EasySpeech

easyspeech interview.m4a > interview.txt
easyspeech *.mp4 --srt --out ~/Captions
easyspeech lecture.mov --txt --timestamps --quiet
```

Your saved corrections apply here too. `--help` lists the options. Shortcuts can call it
through **Run Shell Script**.

## Updates

EasySpeech checks its releases once a day. **Update and Relaunch** downloads, verifies and swaps the app in place, usually in under two seconds. There's a Check Now button and an off switch in **Settings › Updates**.

![The update sheet](docs/update-sheet.png)

Updates don't re-trigger the security prompt, because macOS only quarantines what a *browser* downloads — and the download is verified against the SHA-256 GitHub publishes before anything is installed. [How that works](CONTRIBUTING.md#updates).

---

## Known limits

- **45 languages.** Settings › Languages lists them.
- **No custom models.** Apple manages the acoustic model, so there's no size/quality picker.
- **Punctuation is always on.** Apple gives no toggle, so the app doesn't pretend to offer one.
- **Apple Silicon, macOS 26+.** No fallback for older systems.
- Translation quality is Apple's — good for major languages, weaker for rare pairs.

## Contributing

Build with `./build.sh`, package with `./package.sh`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and the non-obvious things worth knowing before changing the engine.

## Support

EasySpeech is free, has no ads, collects nothing and never will. If it saved you some time, you're welcome to [buy me a coffee](https://buymeacoffee.com/gulfvideo) — entirely optional, and it doesn't unlock anything, because there's nothing locked.

<a href="https://buymeacoffee.com/gulfvideo"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy me a coffee" height="34"></a>

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by [EasyWhisperUI](https://github.com/mehtabmahir/easy-whisper-ui) by [mehtabmahir](https://github.com/mehtabmahir) — a great, genuinely useful app, and the reason this one exists. If you need broader language coverage or specific Whisper models, go use it.
