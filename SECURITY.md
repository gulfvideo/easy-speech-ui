# Security Policy

## Supported versions

Only the latest release gets fixes. EasySpeech updates itself, so there are no
older branches to maintain.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Anything older | No — update first |

## Reporting a vulnerability

Please don't open a public issue for a security problem.

Use [private vulnerability reporting](https://github.com/gulfvideo/easy-speech-ui/security/advisories/new),
which notifies me without the report being visible to anyone else. If that isn't
available to you, email 323723388+gulfvideo@users.noreply.github.com instead.

Tell me what you found, how to reproduce it, and what an attacker could do with
it. I'll confirm I've received it within a week. This is a free app I maintain
on my own time, so I can't promise a fix window, but anything that puts
someone's files or Mac at risk goes to the front of the queue.

## What's worth reporting

EasySpeech transcribes on-device and doesn't send audio anywhere, so most of the
attack surface is in two places:

**The updater.** It downloads a DMG from this repository's releases over HTTPS,
checks it against the SHA-256 GitHub publishes, verifies the code signature and
confirms the bundle identifier before swapping anything. A way to get past any
of those checks, or to make it install something that isn't EasySpeech, is a
real vulnerability.

**File handling.** Malformed audio or video that crashes the app is a bug worth
filing normally. Malformed input that gets code running is a vulnerability.

## What isn't a vulnerability

- **The "Apple could not verify EasySpeech" prompt on first launch.** Expected.
  The app is ad-hoc signed because it's free and I don't pay for a Developer ID.
  See the README.
- **`spctl` reporting the app as rejected.** Same reason. It doesn't block
  launch once you've approved it.
- **Transcripts written next to the source file.** That's the configured output
  location, changeable in Settings.
