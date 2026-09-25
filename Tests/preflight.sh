#!/bin/bash
# Everything that must pass before a release. `package.sh` runs this and refuses to build a
# DMG if it fails, so shipping without it means deliberately going around the packaging script.
#
# Two crashes have shipped from this project, and neither was subtle in hindsight:
#
#   1.2.4  the live-capture tap inherited main-actor isolation and trapped on the audio thread
#   1.2.6  a setting clamped itself inside its own didSet, which recurses under @Observable
#
# Both were in code the tests of the day never *ran*. So the bias here is towards exercising
# real paths over inspecting state: transcribe actual audio, write actual settings, feed it
# actual garbage, and check afterwards that nothing crashed.
#
# Usage:  ./Tests/preflight.sh            full run
#         ./Tests/preflight.sh --quick    skip the slow concurrency stage
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/EasySpeech.app"
BIN="$APP/Contents/MacOS/EasySpeech"
WORK="$(mktemp -d)"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  \033[31m✗\033[0m %s\n' "$1"; }
stage() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# The self-test writes real preferences and restores them, but a crash mid-way would leave
# them modified. Keep a copy either way.
PREFS="$HOME/Library/Preferences/com.easyspeech.ui.plist"
[ -f "$PREFS" ] && cp "$PREFS" "$WORK/prefs.backup"

cleanup() {
    # Unconditional. The self-test writes real preferences and restores them with `defer`,
    # but `defer` does not run when the process takes a signal — and a self-test that crashes
    # is exactly the case this suite exists to produce. Restoring only on success once left
    # the recognition locale set to en-GB.
    if [ -f "$WORK/prefs.backup" ]; then
        cp "$WORK/prefs.backup" "$PREFS"
        defaults read com.easyspeech.ui >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

# Crash reports written during this run are a failure no matter which stage produced them.
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
ls "$CRASH_DIR"/EasySpeech* 2>/dev/null | sort > "$WORK/crashes.before" || true

# ---------------------------------------------------------------------------
stage "Build (includes the self-assigning didSet guard)"
if "$ROOT/build.sh" >"$WORK/build.log" 2>&1; then
    pass "builds clean"
else
    fail "build failed — see $WORK/build.log"
    tail -20 "$WORK/build.log"
    printf '\n\033[31mpreflight aborted: nothing else can run without a build\033[0m\n'
    exit 1
fi

# ---------------------------------------------------------------------------
stage "In-process self-test (settings, queue, export)"
if "$BIN" --self-test >"$WORK/selftest.log" 2>&1; then
    pass "$(cat "$WORK/selftest.log")"
else
    code=$?
    if [ $code -ge 128 ]; then
        fail "self-test CRASHED (signal $((code - 128))) — a setter or queue path is unsafe"
    else
        fail "self-test failed"
    fi
    sed 's/^/      /' "$WORK/selftest.log"
fi

# ---------------------------------------------------------------------------
stage "Transcribe real speech end to end"
# `say` is on every Mac, so the fixture is generated rather than checked in — no binary blobs
# in the repo and the text is known, which is what makes the output checkable.
SPOKEN="The quick brown fox jumps over the lazy dog. This is a test of the transcription engine."
say -o "$WORK/fixture.aiff" "$SPOKEN" 2>/dev/null
if [ -s "$WORK/fixture.aiff" ]; then
    pass "generated a speech fixture"
else
    fail "could not generate a fixture with say(1)"
fi

mkdir -p "$WORK/out"
if "$BIN" "$WORK/fixture.aiff" --txt --srt --vtt --out "$WORK/out" --quiet >"$WORK/cli.log" 2>&1; then
    pass "CLI transcription exits 0"
else
    fail "CLI transcription failed"
    sed 's/^/      /' "$WORK/cli.log"
fi

for ext in txt srt vtt; do
    f="$WORK/out/fixture.$ext"
    if [ -s "$f" ]; then pass ".$ext written and non-empty"; else fail ".$ext missing or empty"; fi
done

# The words themselves must come back. A run that "succeeds" with an empty transcript is the
# exact failure mode the Int16 format bug produced, and it exited 0.
if grep -qi "quick brown fox" "$WORK/out/fixture.txt" 2>/dev/null; then
    pass "transcript contains the spoken words"
else
    fail "transcript does not contain the spoken words — recognition produced nothing usable"
    head -3 "$WORK/out/fixture.txt" 2>/dev/null | sed 's/^/      /'
fi

if grep -q " --> " "$WORK/out/fixture.srt" 2>/dev/null && head -1 "$WORK/out/fixture.srt" | grep -q "^1$"; then
    pass "SRT is well formed"
else
    fail "SRT is malformed"
fi
if head -1 "$WORK/out/fixture.vtt" 2>/dev/null | grep -q "^WEBVTT$"; then
    pass "VTT carries its header"
else
    fail "VTT header missing"
fi

# ---------------------------------------------------------------------------
stage "Audio decode stays off the CoreMedia AudioQueue pipeline"
# Each AVAssetReader audio decode starts a CoreMedia pipeline with its own AudioQueue
# threads. Six at once deadlocked inside AudioToolbox's XPC bridge after nineteen hours.
# Ordinary audio must go through AVAudioFile, which brings up no such pipeline.
"$BIN" "$WORK/fixture.aiff" --txt --out "$WORK/qcheck" --quiet >/dev/null 2>&1 &
QPID=$!
sleep 2
sample $QPID 2 -mayDie >"$WORK/threads.txt" 2>/dev/null || true
wait $QPID 2>/dev/null
QUEUE_THREADS=$(grep -c "coremedia.audioqueue" "$WORK/threads.txt" 2>/dev/null || true)
if [ "${QUEUE_THREADS:-0}" -eq 0 ]; then
    pass "no coremedia.audioqueue threads during an audio decode"
else
    fail "audio decode spawned $QUEUE_THREADS coremedia.audioqueue thread(s) — the deadlock is back"
fi

# ---------------------------------------------------------------------------
stage "Skip files already transcribed"
# Re-running the same file must not produce a second transcript beside the first.
cp "$WORK/fixture.aiff" "$WORK/out/again.aiff"
"$BIN" "$WORK/out/again.aiff" --txt --quiet >/dev/null 2>&1
"$BIN" "$WORK/out/again.aiff" --txt --quiet >/dev/null 2>&1
dupes=$(ls "$WORK/out" | grep -c "again 2" || true)
if [ "$dupes" = "0" ]; then
    pass "re-running a finished file leaves no ' 2' duplicate"
else
    fail "re-running produced $dupes duplicate file(s)"
fi

# ---------------------------------------------------------------------------
stage "Malformed and hostile input"
# None of these should crash, hang, or write a transcript. A non-zero exit is the correct
# answer; a signal is not.
printf 'not audio at all' > "$WORK/bad.mp3"
head -c 4096 /dev/urandom > "$WORK/random.wav"
: > "$WORK/empty.m4a"
head -c 20000 "$WORK/fixture.aiff" > "$WORK/truncated.aiff"

for bad in bad.mp3 random.wav empty.m4a truncated.aiff; do
    "$BIN" "$WORK/$bad" --txt --out "$WORK/out" --quiet >/dev/null 2>&1
    code=$?
    if [ $code -ge 128 ]; then
        fail "$bad crashed the CLI (signal $((code - 128)))"
    else
        pass "$bad rejected without crashing (exit $code)"
    fi
done

# A path that does not exist at all.
"$BIN" "$WORK/nope.mp3" --txt --quiet >/dev/null 2>&1
[ $? -ge 128 ] && fail "missing file crashed the CLI" || pass "missing file handled"

# ---------------------------------------------------------------------------
if [ $QUICK -eq 0 ]; then
stage "Concurrency completes without deadlock"
# The task group claims a slot before claiming a job; a mistake there either miscounts the
# running files or wedges the queue. Running several at once and requiring every output to
# appear is what catches it.
for i in 1 2 3 4 5 6; do cp "$WORK/fixture.aiff" "$WORK/c$i.aiff"; done
started=$(date +%s)
for i in 1 2 3 4 5 6; do
    ( "$BIN" "$WORK/c$i.aiff" --txt --out "$WORK/conc" --quiet >/dev/null 2>&1 ) &
done
wait
elapsed=$(( $(date +%s) - started ))
produced=$(ls "$WORK/conc" 2>/dev/null | grep -c "\.txt$" || true)
if [ "$produced" = "6" ]; then
    pass "6 concurrent transcriptions all completed (${elapsed}s)"
else
    fail "only $produced of 6 concurrent transcriptions completed"
fi
fi

# ---------------------------------------------------------------------------
stage "Release metadata"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Resources/Info.plist")"
# Releases are tagged server-side by `gh release create`, so the local tag list can be
# missing the most recent one entirely — this check once compared 1.3.0 against 1.2.8 while
# 1.2.9 was already published, and would have waved through a duplicate version.
git -C "$ROOT" fetch --tags --quiet 2>/dev/null || true
LATEST_TAG="$(git -C "$ROOT" tag --list 'v*' --sort=-v:refname | head -1 | sed 's/^v//')"

if [ -z "$LATEST_TAG" ]; then
    pass "no previous tag to compare against"
elif [ "$VERSION" = "$LATEST_TAG" ]; then
    fail "version $VERSION is already released — bump Info.plist before packaging"
elif [ "$(printf '%s\n%s\n' "$LATEST_TAG" "$VERSION" | sort -V | tail -1)" = "$VERSION" ]; then
    pass "version $VERSION (build $BUILD) is newer than the last release, $LATEST_TAG"
else
    fail "version $VERSION is older than the last release, $LATEST_TAG"
fi

if "$BIN" --version 2>/dev/null | grep -q "$VERSION"; then
    pass "binary reports $VERSION"
else
    fail "binary does not report $VERSION"
fi

# ---------------------------------------------------------------------------
stage "No crash reports were written during this run"
sleep 2   # the reporter writes asynchronously
ls "$CRASH_DIR"/EasySpeech* 2>/dev/null | sort > "$WORK/crashes.after" || true
NEW_CRASHES="$(comm -13 "$WORK/crashes.before" "$WORK/crashes.after")"
if [ -z "$NEW_CRASHES" ]; then
    pass "no new crash reports"
else
    fail "crash reports appeared during preflight:"
    echo "$NEW_CRASHES" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m%s\033[0m\n' "────────────────────────────────────────"
if [ $FAIL -eq 0 ]; then
    printf '\033[32mpreflight passed — %d checks\033[0m\n' "$PASS"
    exit 0
fi
printf '\033[31mpreflight FAILED — %d of %d checks\033[0m\n' "$FAIL" "$((PASS + FAIL))"
for f in "${FAILURES[@]}"; do printf '  ✗ %s\n' "$f"; done
exit 1
