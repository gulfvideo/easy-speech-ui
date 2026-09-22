# Hyperframes Composition Brief: EasySpeech — "Series A"

## Objective
A launch-announcement video for EasySpeech staged as a 2016 startup funding announcement, played entirely straight.

## Output
- Composition directory: `brag-output-2026-09-17-074531/composition/`
- Rendered video: `brag-output-2026-09-17-074531/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 19.6 seconds

## Source Material
- Project root: `/Users/jackson/Desktop/EasySpeech`
- Primary files read: `README.md`, `docs/screenshot.png`, `EasySpeechArt/EasySpeech-master.svg`
- Product name: EasySpeech
- Strongest claim: 24 hours of audio across 15 files in 954 seconds — 90× realtime, peak memory 39 MB, 2 MB download, zero dependencies
- Key UI to recreate: the main window from `docs/screenshot.png` — file sidebar with green check rows and `0:16 · 38× realtime` subtitles, transcript pane, settings inspector, status bar
- Copy that must appear verbatim:
  - `PRESS RELEASE · SEPTEMBER 2026`
  - `Today we're excited to announce`
  - `our $0 Series A.`
  - `01` / `THE PROBLEM` / `Transcription means uploading your audio to someone else's computer.`
  - `02` / `THE PRODUCT`
  - `03` / `TRACTION`
  - Metric cards: `90×` REALTIME · `2 MB` BUNDLE SIZE · `$0` CLOUD SPEND · `1` ENGINEER
  - Chart label `INFRASTRUCTURE COSTS · 12 MO` ending in `$0`
  - Footnote: `Measured over 24 hours of source audio across 15 files. Peak memory 39 MB. No forward-looking statements.`
  - `EasySpeech` / `We are not hiring.` / `Free forever. There is nothing to buy.` / `github.com/gulfvideo/easy-speech-ui`
  - File rows: `Product Launch Meeting.m4a` 38×, `Field Interview.wav` 74×, `Recorded Lecture.mp4` 51×

## Creative Direction
- Tone preset: `yc-parody`
- Creative direction (user-supplied): **fake Series A launch from 2016**
- Interpretation: Play it completely straight. Hard cuts only — no crossfades. Deck typography: numbered sections, uppercase letterspaced labels over hairline rules, one accent colour, generous white space. Earnest corporate delivery over content about a man who spent nothing. If any element looks like it is *trying* to be funny, it is wrong.
- Angle: every number on screen is true. $0 funding, $0 cloud spend, 1 engineer, 2 MB, 90× realtime — all real and all documented in the README. The comedy is the frame, never an exaggeration.
- Hook: `Today we're excited to announce` → `our $0 Series A.`
- Outro / punchline: `We are not hiring.`
- Avoid:
  - Generic SaaS language
  - Comic fonts, wink-to-camera motion, record scratches, comedy stings
  - Any claim the README does not support
  - Redesigning the app UI — recreate what the screenshot shows

## Visual Identity
- Announcement / outro background: `#051226` → `#144A8A` vertical gradient
- Deck background: `#F7F8FA`
- Deck ink: `#0B1B33`
- Accent: `#2F6FC9`
- Muted / labels: `#4F5A68`
- Display font: `system-ui`, 200–600 weight; +0.18em tracking on uppercase labels, tight on figures
- Figures / chart axis: `ui-monospace`
- References: `docs/screenshot.png` for the window; the icon mark (three waveform bars resolving into three text lines) for the outro

## Storyboard
Use the storyboard in `brag-plan.md` as the creative contract.

Scene summary:
1. **The announcement** — 3.4s — navy; `Today we're excited to announce` → `our $0 Series A.`
2. **01 THE PROBLEM** — 3.0s — white deck slide, one sentence, one hold
3. **02 THE PRODUCT** — 5.0s — the real app window, three files check off with real multipliers
4. **03 TRACTION** — 4.42s — four metric cards, then a flat INFRASTRUCTURE COSTS line at zero, plus a 5pt footnote
5. **Outro** — 3.78s — navy; mark resolves, `We are not hiring.`

## Audio
- Audio role: straight-faced optimistic corporate bed with sparse dry accents (~6 cues)
- Audio arc: bed in at 0.0 → one dry impact on `$0 Series A` → three ticks on the file check-offs → slight lift on the traction slide → one confirm as the metric row completes → fade across the final 1.2s so the punchline is nearly dry
- Music: `happy-beats-business-moves-vol-10-by-ende-dot-app.mp3` (109.96 BPM), copied to `composition/assets/music/`. Deliberately a different track from the earlier cut of this project.
- Music treatment: baseline ~0.34, small lift at 11.4s, fade to 0 over the last 1.2s
- Music cue guidance: bundled preset in this directory. Beat spacing 0.546s. **Lock the outro to the 15.824s strong cue.** Beat grid: check-offs 7.790 / 8.731 / 9.834; metric cards 12.562 / 13.108 / 13.642 / 14.199. The cards are figures, not sentences, so consecutive beats are acceptable **only because all four then hold together ~1.6s** — preserve that hold.
- Audio-reactive treatment: subtle. Background warmth follows music RMS; the outro tile breathes with bass. Nothing else. No bars, no spectrum, no strobing.
- Audio-coupled moments: `$0 Series A` landing (dry impact); three file check-offs (tick each, same timestamp as the green check); metric row completing (one light confirm, not one per card); outro mark resolving (one confirm)
- SFX selection guidance: dry and low. A busy mix reads as "comedy" and kills the deadpan. Prefer low high-frequency-risk files.
- SFX analysis guidance: `~/.claude/skills/brag/assets/sfx/sfx-analysis.md`
- Exact SFX choice: Hyperframes decides filenames, timestamps and volume against the implemented animation.
- Restraint rule: the music must never acknowledge the joke.

## Hyperframes Instructions
Load `hyperframes-core`, `hyperframes-animation`, `hyperframes-creative`, `hyperframes-keyframes`, `hyperframes-cli`. Do not enter the `hyperframes` entry-point intent interview.

Requirements:
- Show the real app UI in Scene 3.
- Reading floors: short label ~0.8s settled, sentence ~0.3s/word. Scene 2's sentence needs its full 2.7s.
- Keep total duration 19.6s.
- Include music and SFX as described.
- Lock the 15.824s strong cue; use the beat grid for the two sequential runs; ignore any cue that hurts readability.
- Hard cuts between scenes — no crossfades.
- Run `npx hyperframes check` before render.
