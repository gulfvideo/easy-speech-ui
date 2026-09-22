# Brag Plan: EasySpeech — "Series A"

## What is this app?
A native macOS transcription app that runs entirely on Apple's on-device Speech framework, transcribes 24 hours of audio in 954 seconds, ships as a 2 MB download with zero dependencies, and was written by one person who has raised no money and has no company.

## The angle
Run the full 2016 startup-announcement playbook — the Medium post, the numbered deck slides, the traction section, the investor-update tone — over a product that has no company, no funding, no cloud bill and no employees.

**The joke is that every number on screen is true.** $0 in funding is true. $0 cloud spend is true. 1 engineer is true. 2 MB is true. 90× realtime is measured. Nothing is exaggerated for the bit; the comedy is entirely in the frame around the facts. That's what keeps it from being a cheap parody — it's a real product wearing a deck.

The 2016 details that sell it: numbered section slides (`01 — THE PROBLEM`), letterspaced uppercase labels with hairline rules, a traction slide, a metrics row, a footnote disclaimer, and the closing "we're hiring" slide — inverted.

## Hook (first 2-3 seconds)
Full-bleed navy announcement card, the exact shape of every funding post from that era:

**"Today we're excited to announce"**
→ beat →
**"our $0 Series A."**

The setup is so familiar the viewer completes it themselves, and the payoff subverts it in three characters. No logo yet.

## Key moments (the middle)
- **`01 — THE PROBLEM`, stated with total deck gravity.** "Transcription means uploading your audio to someone else's computer." It's a real problem delivered in slide voice, which is funnier than a joke would be.
- **`02 — THE PRODUCT`.** The actual EasySpeech window, files checking off with their real multipliers — 38×, 74×, 51×. The bit stops for five seconds and shows the working software, because the product has to survive the frame.
- **`03 — TRACTION`.** Four metric cards: `90× REALTIME`, `2 MB BUNDLE`, `$0 CLOUD SPEND`, `1 ENGINEER`. Beneath them, the 2016 hockey-stick chart — except the line is labelled INFRASTRUCTURE COSTS and it never leaves zero. A footnote in 5pt type nobody is meant to read.

## Outro / punchline
Back to navy. Wordmark, then the slide every one of those posts ended with, inverted:

**"We are not hiring."**

Then, quietly: *Free forever. There is nothing to buy.*

## User flow worth showing
Entry → key action → result, from the real UI:
1. **Entry** — three files sitting in the queue sidebar.
2. **Key action** — each one completes, green check, stamped with its measured realtime multiplier.
3. **Result** — the transcript pane fills with punctuated paragraphs; the status bar reports `55 words · 38× realtime · 1 file written`.

Scene 3 is the centerpiece and recreates `docs/screenshot.png`. The deck slides frame it; they don't replace it.

## Tone
- Preset: `yc-parody` (nearest structural match)
- Creative direction (user-supplied): **fake Series A launch from 2016**
- Interpretation: Play it completely straight. No winking, no comic timing, no funny fonts. Hard cuts, no crossfades. Deck typography: uppercase letterspaced labels over hairline rules, numbered sections, one accent colour, lots of white. The delivery is earnest corporate; the content is a man who spent $0. If any single element looks like it's trying to be funny, it's wrong.

## Format: landscape — 1920x1080
## Duration: 19.6 seconds

## Visual identity (from the project)
Brand navy from `EasySpeech-master.svg`, restaged as a 2016 deck. Bookend slides are navy, the deck body is near-white — deliberately unlike the previous polished cut.

- Announcement / outro background: `#051226` → `#144A8A` vertical gradient
- Deck background: `#F7F8FA`
- Deck ink: `#0B1B33`
- Accent: `#2F6FC9` (the app's `#619EE8` pulled darker so it holds contrast on white)
- Muted / labels: `#4F5A68`
- Display font: `system-ui` at 200–600 weight, tight tracking on numbers, +0.18em on uppercase labels
- Body / metrics font: `ui-monospace` for figures and the chart axis
- Strongest visual element: the app window from `docs/screenshot.png`, and the icon mark (three waveform bars resolving into three text lines) for the outro

## Share copy (draft)
We are pleased to announce EasySpeech has closed a $0 Series A. Cloud spend is $0, headcount is 1, and 24 hours of audio takes 954 seconds. It's free and it runs entirely on your Mac.

## Audio direction
- Role: optimistic corporate bed, straight-faced — the same music a real launch video would use, which is the joke
- Music: `happy-beats-business-moves-vol-10-by-ende-dot-app.mp3` (109.96 BPM). Deliberately a different track from the previous cut so the two films don't sound identical.
- Music treatment: in at 0.0s, bed ~0.34, small lift into the traction slide, fade across the final 1.2s so "We are not hiring." lands nearly dry
- Music cue guidance: bundled preset read. Beat spacing 0.546s. **Strong cue at 15.824s → lock the outro there.** Beat grid: file check-offs at 7.790 / 8.731 / 9.834; metric cards at 12.562 / 13.108 / 13.642 / 14.199. The cards are figures, not sentences, so they may land on consecutive beats **provided all four hold together for ~1.6s afterward** — that hold is the readability budget, not the individual entrances.
- Audio-reactive treatment: subtle — background warmth tracks music RMS on the deck slides, outro tile presence breathes with bass. No bars, no spectrum, no strobing.
- SFX posture: sparse and dry, roughly six cues. `yc-parody` wants restraint; a busy mix would signal "comedy" and kill the deadpan.
- Audio-coupled moments: one soft impact as `$0 Series A` lands, three ticks on the file check-offs, one light confirm as the metric row completes, one confirm on the outro mark
- Restraint rule: no whooshes, no risers, no comedy stings. Absolutely no record-scratch. The music must never acknowledge the joke.

## Storyboard

### Scene 1 — The announcement — 0.0s → 3.4s
Full-bleed navy. Small letterspaced label top-centre: `PRESS RELEASE · SEPTEMBER 2026`.
- `Today we're excited to announce` enters 0.5s, light weight, settles by 1.0s
- `our $0 Series A.` enters 2.0s, large and tight-tracked, holds 1.4s
No logo, no product name.
Sequential/interaction: yes — two-stage reveal, the second line is the payoff.
Audio intent: earnest, optimistic, entirely unaware it's a joke.
Audio-coupled idea: one dry soft impact as `$0 Series A` settles.
Transition mood: hard cut → Scene 2

### Scene 2 — 01 THE PROBLEM — 3.4s → 6.4s
Hard cut to near-white deck slide. Top-left: `01` in accent, `THE PROBLEM` letterspaced beside it, hairline rule beneath running the content width.
- `Transcription means uploading your audio to someone else's computer.` enters 3.7s (9 words, 2.7s hold — exactly its reading floor)
Sequential/interaction: none. One statement, one hold. The restraint is the tone.
Audio intent: unchanged bed. Nothing happens musically; this is a slide.
Transition mood: hard cut → Scene 3

### Scene 3 — 02 THE PRODUCT — 6.4s → 11.4s
Same deck frame, label `02 — THE PRODUCT`. The real EasySpeech window sits on the light slide with a hairline border and soft shadow.
Three file rows check off one at a time with their measured multipliers:
- `Product Launch Meeting.m4a · 38× realtime` at 7.790s
- `Field Interview.wav · 74× realtime` at 8.731s
- `Recorded Lecture.mp4 · 51× realtime` at 9.834s
Transcript paragraphs fade in as the third lands; status bar reports `55 words · 38× realtime · 1 file written`.
Sequential/interaction: yes — three real check-offs on the beat grid, ≥0.9s apart.
Audio intent: work completing, underplayed.
Audio-coupled idea: one soft tick per check-off.
Transition mood: hard cut → Scene 4

### Scene 4 — 03 TRACTION — 11.4s → 15.824s
Label `03 — TRACTION`. Four metric cards arrive left to right on consecutive beats, then **all four hold together for ~1.6s** — that hold is where they're actually read:
- `90×` / REALTIME at 12.562s
- `2 MB` / BUNDLE SIZE at 13.108s
- `$0` / CLOUD SPEND at 13.642s
- `1` / ENGINEER at 14.199s
Beneath, the obligatory chart: a hairline axis labelled `INFRASTRUCTURE COSTS · 12 MO` with a flat line drawing left to right at zero, ending in a small `$0`. It is the only joke in the video that isn't just a true number stated plainly, and it's still a true number.
Footnote, 5pt, `#4F5A68`: `Measured over 24 hours of source audio across 15 files. Peak memory 39 MB. No forward-looking statements.`
Sequential/interaction: yes — four cards on consecutive beats, then the set holds; the chart line draws 13.6s → 15.0s.
Audio intent: the bed lifts very slightly. Corporate confidence.
Audio-coupled idea: one light confirm as the fourth card lands, not one per card.
Transition mood: hard cut → Scene 5

### Scene 5 — Outro — 15.824s → 19.6s
Lands on the **15.824s strong cue**. Back to navy. The icon mark performs itself — three waveform bars, three text lines drawing in — and settles into the app tile.
- `EasySpeech` at 16.2s
- `We are not hiring.` at 16.9s, held to the end
- `Free forever. There is nothing to buy.` at 17.7s
- `github.com/gulfvideo/easy-speech-ui` at 18.5s
Music fades across the final 1.2s.
Sequential/interaction: yes — the mark transformation, then the punchline slide.
Audio intent: arrival, then quiet. The last line is delivered almost dry.
Transition mood: hold to black

**Music mood for this video:** straight-faced optimistic corporate, mixed low, out by the punchline
**Audio summary:** The exact music a real 2016 launch video would use, played completely straight, with six dry cues marking real events — and it clears out before the closing line so the joke lands in near-silence rather than over a swell.
