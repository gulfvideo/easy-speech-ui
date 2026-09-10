// Draws the disk-image background: a caption, an arrow, and a first-launch hint.
// Emits a HiDPI TIFF so it stays crisp on Retina.
// Usage: swift Packaging/MakeDMGBackground.swift <output.tiff>
import AppKit
import Foundation

let width: CGFloat = 640
let height: CGFloat = 400

// Icon centres, matched to the Finder positions set in package.sh.
let appIconCentre = CGPoint(x: 165, y: 185)
let applicationsCentre = CGPoint(x: 475, y: 185)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let pixelsWide = Int(width * scale)
    let pixelsHigh = Int(height * scale)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // Soft vertical wash, cool and light so Finder's icon labels stay legible.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.97, alpha: 1)
    ])?.draw(in: bounds, angle: -90)

    // A faint brand tint bleeding in from the top-left.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.85, alpha: 0.10),
        NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.85, alpha: 0.0)
    ])?.draw(in: bounds, relativeCenterPosition: NSPoint(x: -0.65, y: 0.75))

    let ink = NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.29, alpha: 1)
    let muted = NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.53, alpha: 1)
    let accent = NSColor(calibratedRed: 0.16, green: 0.35, blue: 0.72, alpha: 1)

    func draw(_ text: String, font: NSFont, colour: NSColor, centredAt y: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (width - size.width) / 2, y: y), withAttributes: attributes)
    }

    draw("Install EasySpeech",
         font: .systemFont(ofSize: 26, weight: .semibold), colour: ink, centredAt: 322)
    draw("Drag the app onto the Applications folder",
         font: .systemFont(ofSize: 14, weight: .regular), colour: muted, centredAt: 296)

    // Arrow between the two icons, clear of both.
    let arrowY = appIconCentre.y + 6
    let start = appIconCentre.x + 78
    let end = applicationsCentre.x - 78
    let headLength: CGFloat = 18

    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: start, y: arrowY))
    shaft.line(to: NSPoint(x: end - headLength + 4, y: arrowY))
    shaft.lineWidth = 4
    shaft.lineCapStyle = .round
    accent.withAlphaComponent(0.75).setStroke()
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: end, y: arrowY))
    head.line(to: NSPoint(x: end - headLength, y: arrowY + 11))
    head.line(to: NSPoint(x: end - headLength, y: arrowY - 11))
    head.close()
    accent.withAlphaComponent(0.75).setFill()
    head.fill()

    // First launch is genuinely surprising without a Developer ID, so say it here.
    let hint = "First launch: System Settings › Privacy & Security → Open Anyway"
    let hintFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    let hintAttributes: [NSAttributedString.Key: Any] = [
        .font: hintFont,
        .foregroundColor: muted.withAlphaComponent(0.95)
    ]
    let hintSize = hint.size(withAttributes: hintAttributes)
    let pill = NSRect(x: (width - hintSize.width) / 2 - 14, y: 40,
                      width: hintSize.width + 28, height: hintSize.height + 14)
    NSColor.white.withAlphaComponent(0.7).setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    hint.draw(at: NSPoint(x: (width - hintSize.width) / 2, y: 47), withAttributes: hintAttributes)

    return rep
}

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "dmg-background.tiff")

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("dmgbg-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

var parts: [String] = []
for (scale, name) in [(CGFloat(1), "bg1x.png"), (CGFloat(2), "bg2x.png")] {
    let url = directory.appendingPathComponent(name)
    try render(scale: scale).representation(using: .png, properties: [:])!.write(to: url)
    parts.append(url.path)
}

// tiffutil bundles the two scales into one HiDPI-aware image Finder understands.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
process.arguments = ["-cathidpicheck"] + parts + ["-out", output.path]
try process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Wrote \(output.path)" : "tiffutil failed")
