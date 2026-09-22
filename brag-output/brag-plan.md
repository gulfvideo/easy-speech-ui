# Brag Plan: EasySpeech

## What is this app?
A native macOS transcription app that runs entirely on Apple's on-device Speech framework — no cloud, no API keys, no models to download — and transcribes 24 hours of audio in under 16 minutes on a 2 MB download.

## The angle
This is not an absurd project, so the video should not wink. EasySpeech's claim *is* the joke: every competitor wants your audio uploaded, your credit card, a Python environment and a 3 GB model file. This one is 2 MB and never phones home. The angle is **restraint as a flex** — let the real numbers carry it, because they are genuinely ridiculous and they are all true and measured.

The video must never say "streamline your workflow." It says 954 seconds.

## Hook (first 2-3 seconds)
A waveform scrubbing across black-navy, then the number lands hard:

**"24 hours of audio."**
**"954 seconds."**

That's the whole hook. No product name yet, no logo. A specific, verifiable, faintly absurd measurement that makes a media person stop scrolling. The product reveal is the *payoff* to the number, not the opener.

## Key moments (the middle)
- **The queue actually working.** The real EasySpeech window with three files checking off one at a time, each stamping its own realtime multiplier — 38×, 74×, 51×. Not a diagram of transcription. The app doing it.
- **The three refusals.** "No cloud. No API keys. No subscription." One line at a time, each held. Then the reason: *Apple's on-device Speech framework.* This is the differentiator and it deserves its own beat.
- **The output is real work product.** `.txt` `.srt` `.vtt` chips, word-level timestamps, 45 languages — the things that matter to someone shipping captions, not a feature grid.

## Outro / punchline
Icon, name, then the line that lands the whole thing:

**"Free. No account. Nothing leaves your Mac."**

The punchline is that after 17 seconds of performance claims, the ask is nothing at all.

## User flow worth showing
Entry → key action → result, all present in the real UI:
1. **Entry** — files in the queue sidebar, drag-and-drop origin.
2. **Key action** — each file processes and check-marks with a live realtime multiplier.
3. **Result** — the transcript pane fills with real punctuated paragraphs, and the status bar reports `55 words · 38× realtime · 1 file written`.

Scenes 2 and 4 are the centerpiece and must recreate this from `docs/screenshot.png`. Scene 3 is the only pure-type scene.

## Tone
- Preset: `polished`
- Creative direction: quiet premium utility film — the numbers do the talking, the app does the rest
- Interpretation: Long holds, generous negative space, no bounce or overshoot. Motion is confident and slow-out; type is light-weight with open letter-spacing. The energy comes from the *content* of the claims, never from visual noise. Nothing spins, nothing flashes.

## Format: landscape — 1920x1080
## Duration: 20.5 seconds

> Shipped timing note: Scene 3 runs 8.5→13.5 and Scene 4 runs 13.5→17.0, a half-second later than first drafted, so `Apple's on-device Speech framework.` clears its 1.5s reading floor. Total is unchanged at 20.5s and the 17.02s outro lock still holds.

## Visual identity (from the project)
Taken from `EasySpeechArt/EasySpeech-master.svg` — the app's own gradients.

- Background: `#051226` (deep) → `#144A8A` (upper), vertical gradient, matching the icon tile
- Accent: `#619EE8`
- Mark / highlight: `#9ED4FF` → `#F5FFFF` gradient
- Text: `#F5FFFF` primary, `#9ED4FF` secondary, `#619EE8` for units and labels
- Display font: SF Pro Display / -apple-system, Inter fallback — light to regular weight, generous tracking
- Body font: same family, regular; SF Mono for file names and CLI moments
- Strongest visual element: the icon's waveform-becoming-text mark — three vertical bars resolving into three horizontal lines. That *is* the product in one glyph and should appear as motion, not just as a static logo.

## Share copy (draft)
I got tired of uploading audio to other people's servers, so I built a Mac transcription app that never leaves your machine. 24 hours of audio in 954 seconds, 2 MB, free.

## Audio direction
- Role: warm corporate bed with sparse, motion-matched accents
- Music: `happy-beats-business-moves-vol-1-by-ende-dot-app.mp3` (120.19 BPM)
- Music treatment: start at 0.0s under the waveform, hold a low bed (~0.35 gain) through the type scenes, small lift entering the product reveal, fade out over the final 1.2s so the last line sits in near-silence
- Music cue guidance: preset cue file read. Beat grid is 0.5s at 120 BPM — **too fast for sequential text**, so text reveals snap to every *other* beat (1.0s apart) or slower. Strong cue at **17.02s** → the outro logo reveal must land there. Beat-grid windows: Scene 2 file check-offs at ~4.02 / 5.03 / 6.03; Scene 3 refusal lines at ~9.02 / 10.02 / 11.02.
- Audio-reactive treatment: subtle — the Scene 1 waveform amplitude may follow music RMS, and the icon glow in Scene 5 may breathe with the bed. Nothing else responds. No spectrum bars.
- SFX posture: sparse and professional. Roughly five cues total across 20 seconds.
- Audio-coupled moments: the three file check-offs (soft interface tick each), the `954 seconds` number landing (one dry low impact), the three refusal lines (barely-there tick per line), the outro mark resolving (one soft confirm)
- Restraint rule: no whooshes on transitions, no riser into the outro, no keyboard clatter. If a cue is not matched to something physically moving on screen, it does not go in. Silence under the final line is deliberate — do not fill it.

## Storyboard

### Scene 1 — The number — 0.0s → 3.5s
Deep navy gradient field. A single pale-blue waveform scrubs left to right across the lower third, amplitude reacting subtly to the music bed. Type enters centered, light weight, wide tracking:
- `24 hours of audio.` enters at 0.6s, settles by 1.0s, holds through 3.5s (well past the 1.2s floor)
- `954 seconds.` enters at 2.0s beneath it, larger, `#F5FFFF`, holds 1.5s
No logo, no product name yet.
Sequential/interaction: yes — two-stage type reveal, second line lands on the 2.02 beat.
Audio intent: quiet confidence, a bed establishing under a claim being made calmly.
Audio-coupled idea: one dry low impact as `954 seconds.` settles.
Music: warm bed from 0.0s, low.
Transition mood: clean → Scene 2

### Scene 2 — The app doing it — 3.5s → 8.5s
The real EasySpeech window rises into frame (recreate faithfully from `docs/screenshot.png`): left file sidebar, centre transcript pane, right settings inspector. Window is light-UI against the navy field, soft shadow, slight perspective.
Three file rows check off one at a time, green check filling, each stamping its measured multiplier:
- `Product Launch Meeting.m4a · 38× realtime` at ~4.02s
- `Field Interview.wav · 74× realtime` at ~5.03s
- `Recorded Lecture.mp4 · 51× realtime` at ~6.03s
Transcript paragraphs fade in the centre pane as the third lands. Status bar reads `55 words · 38× realtime · 1 file written`.
Sequential/interaction: yes — three file rows check off one by one on every-other-beat spacing, real filenames and real multipliers from the product.
Audio intent: the satisfaction of work completing without drama.
Audio-coupled idea: soft interface tick per check-off, three total.
Transition mood: soft → Scene 3

### Scene 3 — What it doesn't do — 8.5s → 13.5s
Cut back to the clean navy field. Three short lines, left-aligned, stacked, each arriving 1.0s apart (every other beat) and each holding well past its 0.8s floor:
- `No cloud.` at ~9.02s
- `No API keys.` at ~10.02s
- `No subscription.` at ~11.02s
All three hold together, then a single `#619EE8` line resolves beneath at ~11.9s:
- `Apple's on-device Speech framework.`
Sequential/interaction: yes — three refusals one by one, then the reason.
Audio intent: matter-of-fact. Each line is a fact being set down, not a boast.
Audio-coupled idea: barely-audible tick per line, quieter than Scene 2's.
Transition mood: clean → Scene 4

### Scene 4 — Real work product — 13.5s → 17.0s
Return to the product surface, closer in. A transcript line with a visible timestamp cue, and three format chips arriving together: `.txt` `.srt` `.vtt`. Beneath, two quiet facts in `#9ED4FF`:
- `Word-level timestamps. Cues break at natural pauses.`
- `45 languages · translation on-device`
Sequential/interaction: yes — three format chips arrive in quick succession (0.12s apart; these are labels, not sentences, so they may be tight), then the two lines hold.
Audio intent: competence. The bed lifts very slightly here.
Audio-coupled idea: one light confirm as the chip row completes.
Transition mood: clean → Scene 5

### Scene 5 — Outro — 17.0s → 20.5s
Lands on the **17.02s strong cue**. The icon's mark animates: three vertical waveform bars rotate and resolve into three horizontal text lines — the glyph performing the product. It settles into the full app icon, centered.
- `EasySpeech` at 17.6s, display weight
- `Free. No account. Nothing leaves your Mac.` at 18.4s, held to the end
- `github.com/gulfvideo/easy-speech-ui` small, `#619EE8`, at 19.2s
Music fades out across the final 1.2s; the last line sits in near-silence.
Sequential/interaction: yes — the mark transformation is the hero moment.
Audio intent: arrival, then quiet. The claim is small on purpose.
Audio-coupled idea: one soft confirm as the bars resolve into lines.
Transition mood: hold to black

**Music mood for this video:** upbeat-restrained corporate bed, mixed low throughout, out by the final line
**Audio summary:** A warm bed carries a calm claim, three interface ticks mark real work completing, one dry impact lands the headline number, and everything clears out so the last line — the one that asks for nothing — plays almost dry.

## Voiceover script

Added on request. Kokoro voice `am_michael`, en-US, generated per scene so each line sets its own scene length. The narration **complements** the visuals rather than reading them — the on-screen type carries the numbers, the voice carries the context the screen can't show. Total speech 20.1s, which pushed the cut from 20.5s to 23.6s.

| Clip | Scene | Length | Line |
| --- | --- | --- | --- |
| `vo1` | 1 | 3.43s | A full day of audio. Nothing uploaded anywhere. |
| `vo2` | 2 | 4.65s | It works through a queue on the Neural Engine, so your Mac stays responsive. |
| `vo3` | 3 | 4.44s | No service behind it. Apple's speech model is already on your Mac. |
| `vo4` | 4 | 3.86s | Plain text, or subtitles with real word level timing. |
| `vo5` | 5 | 3.71s | Free, no account, and your audio never leaves the machine. |

Music ducks from 0.30 to 0.13 before the first line and stays there, since narration runs almost continuously; it fades out over the last 1.1s so the closing line plays dry. SFX are pulled down roughly a third from the silent cut so nothing competes with the voice.

**Verification:** the rendered mix was transcribed back through EasySpeech's own CLI and every line returned verbatim, which confirms the voice is intelligible over the bed.

## Deliverables

| File | Format | Length | Audio |
| --- | --- | --- | --- |
| `brag.mp4` | 1920x1080 | 20.5s | music + SFX |
| `brag-vo.mp4` | 1920x1080 | 23.6s | music + SFX + narration |
| `brag-vertical.mp4` | 1080x1920 | 23.6s | music + SFX + narration |

Each has a matching `.jpg` poster baked in as frame 0.

The vertical cut is a re-layout, not a crop: type scales down, and the app window drops its settings inspector to become a narrow sidebar-plus-transcript window — the way EasySpeech actually looks when you make the window small — so the file rows and their realtime multipliers stay readable on a phone.
