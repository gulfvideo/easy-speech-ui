# Hyperframes Composition Brief: EasySpeech

## Objective
Create a short launch-style brag video for EasySpeech, a native macOS transcription app.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 20.5 seconds

## Source Material
- Project root: `/Users/jackson/Desktop/EasySpeech`
- Primary files read: `README.md`, `docs/screenshot.png`, `EasySpeechArt/EasySpeech-master.svg`, `EasySpeechArt/EasySpeech-1024.png`
- Product name: EasySpeech
- Tagline / strongest claim: *24 hours of podcasts and sermons — 15 files — transcribed in 954 seconds. That's 90× realtime, peak memory 39 MB.*
- Key UI or visual moment to recreate: the main window in `docs/screenshot.png` — left file sidebar with green check rows and `0:16 · 38× realtime` subtitles, centre transcript pane with punctuated paragraphs, right settings inspector with Output Files toggles. Bottom status bar reads `3 files · 0:15 / 0:16 · 55 words · 38× realtime · 1 file written`.
- Copy that must appear verbatim:
  - `24 hours of audio.`
  - `954 seconds.`
  - `No cloud.`
  - `No API keys.`
  - `No subscription.`
  - `Apple's on-device Speech framework.`
  - `Word-level timestamps. Cues break at natural pauses.`
  - `45 languages · translation on-device`
  - `EasySpeech`
  - `Free. No account. Nothing leaves your Mac.`
  - `github.com/gulfvideo/easy-speech-ui`
  - File rows: `Product Launch Meeting.m4a` (38× realtime), `Field Interview.wav` (74× realtime), `Recorded Lecture.mp4` (51× realtime)

## Creative Direction
- Tone preset: `polished`
- Creative direction: quiet premium utility film — the numbers do the talking, the app does the rest
- Interpretation: Long holds, generous negative space, no bounce or overshoot anywhere. Slow-out easing, light type weights, open letter-spacing. Energy comes from the content of the claims, never from visual noise. Nothing spins, strobes, or flashes.
- Angle: EasySpeech is not an absurd project, so the video must not wink. Every competitor wants your audio uploaded, your credit card, a Python environment and a multi-gigabyte model file. This one is a 2 MB download that never phones home, and the real measured numbers are startling enough to carry the whole video. Restraint is the flex.
- Hook: a waveform scrubbing across deep navy, then `24 hours of audio.` followed by `954 seconds.` — no logo, no product name until the payoff.
- Outro / punchline: `Free. No account. Nothing leaves your Mac.` — after 17 seconds of performance claims, the ask is nothing at all.
- Avoid:
  - Generic SaaS language ("streamline", "effortless", "supercharge") — banned outright
  - Abstract filler visuals, particle systems, spectrum bars, musical notes
  - Any redesign of the app UI — recreate what `docs/screenshot.png` actually shows
  - Claiming anything the README does not support

## Visual Identity
Exact values from the app's own `EasySpeech-master.svg` gradients.

- Background: vertical gradient `#144A8A` (top) → `#051226` (bottom)
- Text: `#F5FFFF` primary, `#9ED4FF` secondary
- Accent: `#619EE8` (units, labels, URL)
- Mark gradient: `#F5FFFF` → `#9ED4FF`
- Display font: SF Pro Display / `-apple-system`, Inter fallback — light to regular weight, generous tracking
- Body font: same family regular; SF Mono / ui-monospace for file names
- Visual references from the project:
  - `EasySpeechArt/EasySpeech-1024.png` — the app icon, for the outro
  - The icon's mark: three vertical waveform bars resolving into three horizontal text lines. This glyph *is* the product and should animate, not sit static.
  - `docs/screenshot.png` — the window to recreate in Scenes 2 and 4

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. **The number** — 3.5s — waveform scrub; `24 hours of audio.` then `954 seconds.` lands
2. **The app doing it** — 5.0s — real EasySpeech window; three file rows check off one by one with their real multipliers; transcript fills; status bar
3. **What it doesn't do** — 4.5s — `No cloud.` / `No API keys.` / `No subscription.` one per 1.0s, then `Apple's on-device Speech framework.`
4. **Real work product** — 4.0s — `.txt` `.srt` `.vtt` chips arrive; timestamps and languages lines hold
5. **Outro** — 3.5s — mark resolves bars→lines, icon settles, name, punchline, URL

## Audio
- Audio role: warm corporate bed with sparse, motion-matched accents (~5 cues total across 20.5s)
- Audio arc: bed establishes low under the hook → one dry impact lands `954 seconds.` → three soft interface ticks mark real work completing → quieter ticks under the refusals → slight lift into the format chips → bed fades across the final 1.2s so the punchline plays almost dry
- Music: `happy-beats-business-moves-vol-1-by-ende-dot-app.mp3` (120.19 BPM), copied to `composition/assets/music/`
- Music treatment: start 0.0s, hold ~0.35 gain, small lift entering Scene 4, fade out over the last 1.2s. The final line must not have music under it.
- Music cue guidance: bundled preset at `~/.claude/skills/brag/assets/music/cues/happy-beats-business-moves-vol-1-by-ende-dot-app.music-cues.json`. Beat grid is 0.5s at 120 BPM — **too fast for sequential text**, so text snaps to every *other* beat (1.0s) or slower. Targets: **strong cue 17.02s → lock the outro mark reveal there**. Beat-grid windows: Scene 2 check-offs ~4.02 / 5.03 / 6.03; Scene 3 refusal lines ~9.02 / 10.02 / 11.02.
- Audio-reactive treatment: subtle. The Scene 1 waveform amplitude may follow music RMS, and the Scene 5 icon glow may breathe with the bed. Nothing else responds. No spectrum bars, no strobing.
- Audio-coupled moments:
  - Scene 1, `954 seconds.` settling — one dry low impact, the single loudest cue in the video
  - Scene 2, three file check-offs — soft interface tick each, fired at the same timestamp as the green check
  - Scene 3, three refusal lines — barely-audible tick per line, quieter than Scene 2's
  - Scene 4, format chip row completing — one light confirm
  - Scene 5, bars resolving into lines — one soft confirm, may ring over the fading bed
- SFX selection guidance: every cue must match something physically moving on screen. No transition whooshes, no riser into the outro, no keyboard clatter. If the edit feels busy, drop a cue rather than add one.
- SFX analysis guidance: `~/.claude/skills/brag/assets/sfx/sfx-analysis.md` — prefer low high-frequency-risk files, since the check-off tick repeats three times and the tone is polished.
- Exact SFX choice: Hyperframes should choose filenames, timestamps, density, and volume based on the implemented animation.
- Audio files: copy the chosen music and any selected SFX into `brag-output/composition/assets/`

## Hyperframes Instructions
Load the composition-building Hyperframes domain skills — `hyperframes-core`, `hyperframes-animation`, `hyperframes-creative`, `hyperframes-keyframes`, `hyperframes-cli`. Do not enter the `hyperframes` entry-point intent interview or route into its generic promo / launch-video workflow. Prefer native Hyperframes conventions over anything in `/brag`.

Requirements:
- Show at least one real UI element from the source project — Scenes 2 and 4 recreate `docs/screenshot.png`.
- Keep all text readable: short labels ~0.8s settled minimum, sentences ~0.3s per word. The hook gets the most.
- Keep the video within 15–25 seconds (target 20.5s).
- Include the music and SFX layer as described.
- Treat the audio notes as guidance; choose SFX after the visual animation exists.
- Treat cue metadata as optional hints. Lock the 17.02s strong cue for the outro; use the beat grid for the two sequential runs; ignore any cue that hurts readability.
- Use local assets for audio and any runtime dependency.
- Run `npx hyperframes check` before render — it is the single gate.
