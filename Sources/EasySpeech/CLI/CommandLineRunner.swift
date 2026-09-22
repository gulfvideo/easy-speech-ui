import Foundation

/// Headless transcription, so EasySpeech can be scripted or driven from a Shortcut's
/// "Run Shell Script" action.
///
/// The app binary doubles as the command line tool rather than shipping a second
/// executable: one build, one code signature, and no way for the two to drift apart.
enum CommandLineRunner {

    /// Arguments macOS itself passes when launching a bundled app.
    private static func isSystemArgument(_ argument: String) -> Bool {
        argument.hasPrefix("-psn_") || argument.hasPrefix("-NS") || argument == "YES" || argument == "NO"
    }

    /// True when the process was invoked as a tool rather than launched as an app.
    ///
    /// Any real argument means the CLI. Launch Services delivers documents by Apple
    /// event — Finder's "Open With", `open -a`, and dropping onto the Dock all reach the
    /// app delegate, never argv — so a file path here can only have come from a shell.
    ///
    /// Deliberately not gated on `isatty`: scripts, CI and Shortcuts' "Run Shell Script"
    /// all pipe their output, and launching a GUI in those contexts would hang the caller.
    static func shouldHandle(_ arguments: [String]) -> Bool {
        !arguments.filter { !isSystemArgument($0) }.isEmpty
    }

    struct Options {
        var files: [URL] = []
        var writeText = false
        var writeSRT = false
        var writeVTT = false
        var timestamps = false
        var toStdout = false
        var quiet = false
        /// Re-transcribe even when the output is already there. Off by default, matching the app.
        var force = false
        var locale: String?
        var outputDirectory: URL?

        var writesFiles: Bool { writeText || writeSRT || writeVTT }
    }

    // MARK: - Entry

    /// Bridges the async work back to a synchronous `main`.
    /// True when every file this invocation would write already exists in the destination.
    ///
    /// Requires *all* requested formats, so `--srt` after an earlier `--txt` run still does the
    /// work rather than treating the file as finished.
    private static func alreadyTranscribed(_ file: URL, options: Options) -> Bool {
        let folder = options.outputDirectory ?? file.deletingLastPathComponent()
        let base = file.deletingPathExtension().lastPathComponent

        var wanted: [String] = []
        if options.writeText { wanted.append("txt") }
        if options.writeSRT { wanted.append("srt") }
        if options.writeVTT { wanted.append("vtt") }
        guard !wanted.isEmpty else { return false }

        return wanted.allSatisfy {
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(base).appendingPathExtension($0).path)
        }
    }

    static func runSynchronously(_ arguments: [String]) -> Never {
        // Handled here, before the semaphore below parks the main thread. `SelfTest` is
        // @MainActor, and nothing main-actor-isolated can ever be scheduled once this
        // function is waiting — which is also why the transcription path stays nonisolated.
        if arguments.contains("--self-test") {
            exit(MainActor.assumeIsolated { SelfTest.run() })
        }

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var code: Int32 = 0
        Task {
            code = await run(arguments)
            semaphore.signal()
        }
        semaphore.wait()
        exit(code)
    }

    static func run(_ arguments: [String]) async -> Int32 {
        let meaningful = arguments.filter { !isSystemArgument($0) }

        if meaningful.contains("--help") || meaningful.contains("-h") {
            print(usage)
            return 0
        }
        if meaningful.contains("--version") {
            print(version)
            return 0
        }

        let options: Options
        do {
            options = try parse(meaningful)
        } catch {
            FileHandle.standardError.write(Data("easyspeech: \(error.localizedDescription)\n\n".utf8))
            print(usage)
            return 64                                     // EX_USAGE
        }

        guard !options.files.isEmpty else {
            FileHandle.standardError.write(Data("easyspeech: no input files\n\n".utf8))
            print(usage)
            return 64
        }

        var failures = 0
        for file in options.files {
            do {
                try await transcribe(file, options: options)
            } catch {
                failures += 1
                FileHandle.standardError.write(
                    Data("easyspeech: \(file.lastPathComponent): \(error.localizedDescription)\n".utf8))
            }
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - Work

    private static func transcribe(_ file: URL, options: Options) async throws {
        let defaults = UserDefaults.standard
        // Share the app's saved corrections so scripted runs match interactive ones.
        let corrections = defaults.data(forKey: "corrections")
            .flatMap { try? JSONDecoder().decode([Correction].self, from: $0) } ?? []

        let localeIdentifier = options.locale
            ?? defaults.string(forKey: "localeIdentifier")
            ?? Locale.current.identifier.replacingOccurrences(of: "_", with: "-")

        let transcriberOptions = FileTranscriber.Options(
            locale: Locale(identifier: localeIdentifier),
            censorProfanity: defaults.bool(forKey: "censorProfanity"),
            vocabulary: corrections.map(\.replacement),
            corrections: corrections
        )

        // Skip before decoding anything, so re-running a folder costs nothing. Matches the
        // app's "Skip files already transcribed" setting; `--force` overrides both.
        if !options.force, options.writesFiles, alreadyTranscribed(file, options: options) {
            if !options.quiet {
                FileHandle.standardError.write(
                    Data("Skipping \(file.lastPathComponent) — already transcribed\n".utf8))
            }
            return
        }

        if !options.quiet {
            FileHandle.standardError.write(Data("Transcribing \(file.lastPathComponent)…\n".utf8))
        }

        let transcript = try await FileTranscriber.transcribe(url: file, options: transcriberOptions) { stage in
            guard !options.quiet, case .transcribing(let fraction) = stage else { return }
            let percent = Int(fraction * 100)
            if percent % 10 == 0 {
                FileHandle.standardError.write(Data("  \(percent)%\r".utf8))
            }
        }

        if !options.quiet {
            FileHandle.standardError.write(Data("  done\n".utf8))
        }

        // Default behaviour with no format flags is to print, so it can be piped.
        if options.toStdout || !options.writesFiles {
            print(SubtitleWriter.text(for: transcript, timestamps: options.timestamps), terminator: "")
        }

        guard options.writesFiles else { return }
        let folder = options.outputDirectory ?? file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = file.deletingPathExtension().lastPathComponent

        func write(_ contents: String, _ ext: String) throws {
            // Only write what's missing. Adding --srt to a file that already has a .txt should
            // produce the subtitle and leave the transcript alone, not a second copy of it.
            let existing = folder.appendingPathComponent(base).appendingPathExtension(ext)
            if !options.force, FileManager.default.fileExists(atPath: existing.path) { return }
            let target = JobQueue.nonClobberingURL(folder: folder, base: base, ext: ext)
            try contents.write(to: target, atomically: true, encoding: .utf8)
            if !options.quiet {
                FileHandle.standardError.write(Data("  wrote \(target.lastPathComponent)\n".utf8))
            }
        }
        if options.writeText {
            try write(SubtitleWriter.text(for: transcript, timestamps: options.timestamps), "txt")
        }
        if options.writeSRT { try write(SubtitleWriter.srt(for: transcript), "srt") }
        if options.writeVTT { try write(SubtitleWriter.vtt(for: transcript), "vtt") }
    }

    // MARK: - Parsing

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--txt":         options.writeText = true
            case "--srt":         options.writeSRT = true
            case "--vtt":         options.writeVTT = true
            case "--timestamps":  options.timestamps = true
            case "--stdout":      options.toStdout = true
            case "--quiet", "-q": options.quiet = true
            case "--force":       options.force = true
            case "--locale":
                index += 1
                guard index < arguments.count else { throw ParseError(message: "--locale needs a value, e.g. en-US") }
                options.locale = arguments[index]
            case "--out":
                index += 1
                guard index < arguments.count else { throw ParseError(message: "--out needs a directory") }
                options.outputDirectory = URL(fileURLWithPath: arguments[index])
            default:
                if argument.hasPrefix("-") {
                    throw ParseError(message: "unknown option \(argument)")
                }
                let url = URL(fileURLWithPath: argument)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ParseError(message: "no such file: \(argument)")
                }
                options.files.append(url)
            }
            index += 1
        }
        return options
    }

    // MARK: - Help

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "EasySpeech \(short)"
    }

    static let usage = """
    \(version)

    USAGE
      easyspeech <file>… [options]

    Transcribes on this Mac using Apple's Speech framework. With no format option the
    transcript is printed to standard output, so it can be piped or captured.

    OPTIONS
      --txt              write a .txt beside the source
      --srt              write subtitles
      --vtt              write web subtitles
      --out <dir>        write output files here instead
      --timestamps       prefix each paragraph with its time (text output)
      --stdout           print the transcript as well as writing files
      --locale <id>      spoken language, e.g. en-US (default: the app's setting)
      -q, --quiet        no progress on stderr
      --force            re-transcribe even if the output is already there
      -h, --help         this text
      --version          version only

    NOTES
      Correction rules saved in the app are applied here too.
      Existing files are never overwritten; a numbered name is used instead.

    EXAMPLES
      easyspeech interview.m4a > interview.txt
      easyspeech *.mp3 --srt --out ~/Captions
      easyspeech lecture.mov --txt --timestamps --quiet
    """
}
