import Foundation

/// In-process checks that run before every release, via `EasySpeech --self-test`.
///
/// These exist because of two crashes that shipped. Both were in code the tests of the day
/// never *executed*:
///
/// * 1.2.4 — the live-capture tap inherited main-actor isolation and trapped on the audio
///   thread. Never run, because testing it needed microphone permission.
/// * 1.2.6 — `concurrentJobs` clamped itself inside its own `didSet`, which recurses under
///   `@Observable`. Never run, because every test *read* settings and none *wrote* them.
///
/// So the rule here is: touch the paths a user touches. Write every setting, don't just read
/// it. Drive the queue, don't just inspect it. Anything that only looks at state is not
/// pulling its weight.
///
/// End-to-end transcription lives in `Tests/preflight.sh`, which drives the built binary over
/// real audio. This half is pure logic and runs in well under a second.
@MainActor
enum SelfTest {

    private nonisolated(unsafe) static var failures: [String] = []
    private nonisolated(unsafe) static var checks = 0

    private static func expect(_ condition: Bool, _ what: String) {
        checks += 1
        if !condition { failures.append(what) }
    }

    private static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ what: String) {
        checks += 1
        if a != b { failures.append("\(what) — got \(a), expected \(b)") }
    }

    static func run() -> Int32 {
        failures = []
        checks = 0

        settingsSurviveBeingWritten()
        concurrencyIsClampedWhereItIsRead()
        skipDetectionMatchesTheDestination()
        queueReorderKeepsRunningFilesPut()
        subtitleOutputIsWellFormed()
        numberRepairLeavesRealNumbersAlone()
        correctionsAreExactNotFuzzy()

        if failures.isEmpty {
            print("self-test: \(checks) checks passed")
            return 0
        }
        FileHandle.standardError.write(Data("self-test: \(failures.count) of \(checks) FAILED\n".utf8))
        for f in failures {
            FileHandle.standardError.write(Data("  ✗ \(f)\n".utf8))
        }
        return 1
    }

    // MARK: - The one that would have caught 1.2.6

    /// Writes every stored setting, including out-of-range values.
    ///
    /// A property that clamps itself inside its own `didSet` recurses until the stack runs
    /// out, and `@Observable` makes that invisible at the call site. Nothing catches it except
    /// actually performing the write, so this performs every write. If a setting is added and
    /// not listed here, that is the gap.
    ///
    /// Real preferences are restored afterwards — this runs against `UserDefaults.standard`
    /// because that is what `AppSettings` uses, and a test that dodged it would dodge the bug.
    private static func settingsSurviveBeingWritten() {
        let s = AppSettings.shared

        let saved = (
            locale: s.localeIdentifier, censor: s.censorProfanity, appearance: s.appearance,
            txt: s.writeText, srt: s.writeSRT, vtt: s.writeVTT, stamps: s.timestampsInText,
            location: s.outputLocation, customPath: s.customOutputPath,
            reveal: s.revealWhenDone, open: s.openWhenDone, corrections: s.corrections,
            watchOn: s.watchFolderEnabled, watchPath: s.watchFolderPath,
            input: s.inputDeviceUID, concurrent: s.concurrentJobs, skip: s.skipAlreadyTranscribed,
            autoUpdate: s.automaticUpdateChecks, lastCheck: s.lastUpdateCheck,
            translate: s.translate, target: s.translationTarget
        )
        defer {
            s.localeIdentifier = saved.locale; s.censorProfanity = saved.censor
            s.appearance = saved.appearance; s.writeText = saved.txt
            s.writeSRT = saved.srt; s.writeVTT = saved.vtt
            s.timestampsInText = saved.stamps; s.outputLocation = saved.location
            s.customOutputPath = saved.customPath; s.revealWhenDone = saved.reveal
            s.openWhenDone = saved.open; s.corrections = saved.corrections
            s.watchFolderEnabled = saved.watchOn; s.watchFolderPath = saved.watchPath
            s.inputDeviceUID = saved.input; s.concurrentJobs = saved.concurrent
            s.skipAlreadyTranscribed = saved.skip; s.automaticUpdateChecks = saved.autoUpdate
            s.lastUpdateCheck = saved.lastCheck; s.translate = saved.translate
            s.translationTarget = saved.target
        }

        // Every one of these is a write. Reaching the line after each is the assertion.
        s.localeIdentifier = "en-GB";            expectEqual(s.localeIdentifier, "en-GB", "localeIdentifier")
        s.censorProfanity.toggle();              _ = s.censorProfanity
        s.appearance = .dark;                    expectEqual(s.appearance, .dark, "appearance")
        s.writeText = true;                      expect(s.writeText, "writeText")
        s.writeSRT = true;                       expect(s.writeSRT, "writeSRT")
        s.writeVTT = true;                       expect(s.writeVTT, "writeVTT")
        s.timestampsInText.toggle();             _ = s.timestampsInText
        s.outputLocation = .customFolder;        expectEqual(s.outputLocation, .customFolder, "outputLocation")
        s.customOutputPath = "/tmp/es-selftest"; expectEqual(s.customOutputPath, "/tmp/es-selftest", "customOutputPath")
        s.revealWhenDone.toggle();               _ = s.revealWhenDone
        s.openWhenDone.toggle();                 _ = s.openWhenDone
        s.corrections = [Correction(heard: "Ensure if I", replacement: "Ensurify")]
        expectEqual(s.corrections.count, 1, "corrections")
        s.watchFolderEnabled.toggle();           _ = s.watchFolderEnabled
        s.watchFolderPath = "/tmp";              expectEqual(s.watchFolderPath, "/tmp", "watchFolderPath")
        s.inputDeviceUID = "selftest-uid";       expectEqual(s.inputDeviceUID, "selftest-uid", "inputDeviceUID")
        s.skipAlreadyTranscribed.toggle();       _ = s.skipAlreadyTranscribed
        s.automaticUpdateChecks.toggle();        _ = s.automaticUpdateChecks
        s.lastUpdateCheck = Date();              expect(s.lastUpdateCheck != nil, "lastUpdateCheck")
        s.translate.toggle();                    _ = s.translate
        s.translationTarget = "fr";              expectEqual(s.translationTarget, "fr", "translationTarget")

        // The exact property that crashed, written across and beyond its whole range.
        for n in [1, 2, 3, 4, 5, 6, 0, -1, 99, Int.max, Int.min, 6] {
            s.concurrentJobs = n
            expect(AppSettings.clampConcurrency(s.concurrentJobs) >= 1, "concurrentJobs survived \(n)")
        }
    }

    private static func concurrencyIsClampedWhereItIsRead() {
        expectEqual(AppSettings.clampConcurrency(0), 1, "clamp below range")
        expectEqual(AppSettings.clampConcurrency(-5), 1, "clamp negative")
        expectEqual(AppSettings.clampConcurrency(99), 6, "clamp above range")
        expectEqual(AppSettings.clampConcurrency(Int.max), 6, "clamp Int.max")
        expectEqual(AppSettings.clampConcurrency(Int.min), 1, "clamp Int.min")
        expectEqual(AppSettings.clampConcurrency(4), 4, "leave in-range alone")
        expectEqual(AppSettings.concurrencyRange.lowerBound, 1, "range floor")
        expectEqual(AppSettings.concurrencyRange.upperBound, 6, "range ceiling")
    }

    /// The skip check must look at the destination, and must want every enabled format.
    private static func skipDetectionMatchesTheDestination() {
        let s = AppSettings.shared
        let savedLocation = s.outputLocation
        let savedPath = s.customOutputPath
        let savedTxt = s.writeText, savedSRT = s.writeSRT, savedVTT = s.writeVTT
        defer {
            s.outputLocation = savedLocation; s.customOutputPath = savedPath
            s.writeText = savedTxt; s.writeSRT = savedSRT; s.writeVTT = savedVTT
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("es-selftest-skip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("episode.mp3")
        FileManager.default.createFile(atPath: source.path, contents: Data("x".utf8))

        s.outputLocation = .alongsideSource
        s.writeText = true; s.writeSRT = false; s.writeVTT = false

        let queue = JobQueue()
        expectEqual(queue.add([source]), 1, "queues a file with no transcript")
        expectEqual(queue.lastSkippedCount, 0, "nothing skipped when no transcript exists")

        // Now the transcript exists.
        try? "text".write(to: dir.appendingPathComponent("episode.txt"), atomically: true, encoding: .utf8)
        let queue2 = JobQueue()
        expectEqual(queue2.add([source]), 0, "skips a file whose transcript is already there")
        expectEqual(queue2.lastSkippedCount, 1, "reports what it skipped")

        // Turning on another format must un-skip it rather than call the job done.
        s.writeSRT = true
        let queue3 = JobQueue()
        expectEqual(queue3.add([source]), 1, "re-runs when a newly enabled format is missing")

        // A custom destination is what gets checked, not the source folder.
        s.writeSRT = false
        let elsewhere = dir.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        s.outputLocation = .customFolder
        s.customOutputPath = elsewhere.path
        let queue4 = JobQueue()
        expectEqual(queue4.add([source]), 1, "source-folder transcript doesn't count for a custom destination")
    }

    /// Reordering must never disturb files that are already running.
    private static func queueReorderKeepsRunningFilesPut() {
        let s = AppSettings.shared
        let savedSkip = s.skipAlreadyTranscribed
        s.skipAlreadyTranscribed = false
        defer { s.skipAlreadyTranscribed = savedSkip }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("es-selftest-order-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var urls: [URL] = []
        for i in 0..<5 {
            let u = dir.appendingPathComponent("f\(i).mp3")
            FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
            urls.append(u)
        }

        let queue = JobQueue()
        expectEqual(queue.add(urls), 5, "queued all five")

        // Simulate the first two already transcribing.
        queue.jobs[0].state = .preparing
        queue.jobs[1].state = .transcribing
        queue.jobs[1].progress = 0.5

        let last = queue.jobs[4]
        expect(queue.canMoveToTopOfQueue(last), "last waiting file can move")
        expect(!queue.canMoveToTopOfQueue(queue.jobs[0]), "a running file cannot move")

        queue.moveToTopOfQueue(last)
        expectEqual(queue.jobs[0].url, urls[0], "running file stayed at 0")
        expectEqual(queue.jobs[1].url, urls[1], "running file stayed at 1")
        expectEqual(queue.jobs[2].url, urls[4], "moved file landed in front of the waiting ones")

        expect(!queue.canMoveToTopOfQueue(queue.jobs[2]), "already first in line is a no-op")
        let before = queue.jobs.map(\.url)
        queue.moveToTopOfQueue(queue.jobs[2])
        expectEqual(queue.jobs.map(\.url), before, "no-op really changed nothing")

        expect(queue.hasQueuedWork, "still has waiting work")
        queue.cancelAll()
        expect(!queue.isPaused, "cancel clears the paused flag")
        expect(queue.jobs.allSatisfy(\.state.isTerminal), "cancel leaves every job terminal")
    }

    // MARK: - Export

    private static func subtitleOutputIsWellFormed() {
        var t = Transcript()
        t.segments = [
            TranscriptSegment(text: "First line here.", start: 0, end: 2.48,
                              words: [TimedWord(text: "First ", start: 0, end: 0.5),
                                      TimedWord(text: "line ", start: 0.5, end: 1.2),
                                      TimedWord(text: "here.", start: 1.2, end: 2.48)]),
            TranscriptSegment(text: "Second one.", start: 3.1, end: 4.9,
                              words: [TimedWord(text: "Second ", start: 3.1, end: 4.0),
                                      TimedWord(text: "one.", start: 4.0, end: 4.9)])
        ]

        let srt = SubtitleWriter.srt(for: t)
        expect(srt.hasPrefix("1\n"), "SRT starts at cue 1")
        expect(srt.contains(" --> "), "SRT has a cue arrow")
        expect(srt.contains(","), "SRT uses a comma for milliseconds")
        expect(!srt.contains("WEBVTT"), "SRT has no WEBVTT header")
        expect(srt.hasSuffix("\n"), "SRT ends with a newline")

        let vtt = SubtitleWriter.vtt(for: t)
        expect(vtt.hasPrefix("WEBVTT\n\n"), "VTT starts with its header")
        expect(vtt.contains("."), "VTT uses a dot for milliseconds")

        expectEqual(SubtitleWriter.timecode(0, separator: ","), "00:00:00,000", "zero timecode")
        expectEqual(SubtitleWriter.timecode(3661.5, separator: ","), "01:01:01,500", "hour timecode")
        expectEqual(SubtitleWriter.timecode(-5, separator: ","), "00:00:00,000", "negative clamps to zero")

        // An empty transcript must produce something writable, not a crash or a stray cue.
        let empty = SubtitleWriter.srt(for: Transcript())
        expect(!empty.contains("-->"), "empty transcript yields no cues")

        let text = SubtitleWriter.text(for: t, timestamps: true)
        expect(text.contains("[0:00]"), "timestamped text carries a mark")
        expect(!SubtitleWriter.text(for: t, timestamps: false).contains("[0:00]"), "plain text carries none")

        // Long text has to wrap rather than run off the frame.
        let wrapped = SubtitleWriter.wrap(String(repeating: "word ", count: 40), limit: 42)
        expect(wrapped.contains("\n"), "long cue wraps")
        expect(wrapped.split(separator: "\n").allSatisfy { $0.count <= 60 }, "no wrapped line runs long")
    }

    private static func numberRepairLeavesRealNumbersAlone() {
        expectEqual(SpokenNumbers.polish("1000000s of people"), "millions of people", "pluralized scale")
        expectEqual(SpokenNumbers.polish("the 1st version"), "the first version", "small ordinal")
        expectEqual(SpokenNumbers.polish("no digits here"), "no digits here", "digit-free text untouched")

        // The rules must not touch things that are correct as digits.
        for untouched in ["in 1997", "call 555-0134", "100% correct", "May 1st", "21st century", "$4.50"] {
            expectEqual(SpokenNumbers.polish(untouched), untouched, "left alone: \(untouched)")
        }
    }

    private static func correctionsAreExactNotFuzzy() {
        let rules = [Correction(heard: "Ensure if I", replacement: "Ensurify"),
                     Correction(heard: "Ann", replacement: "Anne")]

        expectEqual(VocabularyCorrector.correct("Ensure if I is great", using: rules),
                    "Ensurify is great", "exact phrase replaced")
        expectEqual(VocabularyCorrector.correct("ensure   if  i is great", using: rules),
                    "Ensurify is great", "case and spacing tolerated")
        expectEqual(VocabularyCorrector.correct("the channel", using: rules),
                    "the channel", "must not fire inside a longer word")
        expectEqual(VocabularyCorrector.correct("", using: rules), "", "empty input")
        expectEqual(VocabularyCorrector.correct("nothing to do", using: []), "nothing to do", "no rules")
    }
}
