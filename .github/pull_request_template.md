## What this changes

<!-- One or two sentences. What's different after this lands? -->

## Why

<!-- The problem it solves. If it fixes an issue, write "Fixes #123". -->

## How it was tested

<!--
What you actually ran, not what you intended to. For example:

- Transcribed a 40 minute MP3, output matched the previous build
- Live dictation, started and stopped three times, no crash
- ./build.sh clean
-->

## Checklist

- [ ] `./build.sh` succeeds with no new warnings
- [ ] Tested on a real file or a real recording, not just a build
- [ ] README or CONTRIBUTING updated if behaviour changed

<!--
Heads up: EasySpeech targets macOS 26 and Apple Silicon, and uses Apple's Speech
framework only. Pull requests adding a cloud service, an API key, or a bundled
model won't be merged — that's the whole point of the app. Open an issue first
if you're planning something large.
-->
