# EasySpeech icons

Clean vector recreation of the approved Wave to Words concept. The mark retains the curved waveform-to-text connection. The app name is intentionally omitted from the icon for legibility.

## Included
- EasySpeech.icns: macOS app icon.
- Assets.xcassets/AppIcon.appiconset: complete standard Mac app icon slots, 16 through 1024 pixels.
- Assets.xcassets/MenuBarIcon.imageset: black alpha template PNGs at 18, 36, and 54 pixels. macOS supplies the appropriate light/dark tint.
- EasySpeech.iconset: source PNGs for iconutil.
- EasySpeech-1024.png: high resolution transparent PNG.
- EasySpeech-master.svg: editable vector master, with transparent outer margins.
- EasySpeech-symbol-black.svg and EasySpeech-symbol-white.svg: standalone vector marks.

## Xcode
Drag AppIcon.appiconset and MenuBarIcon.imageset into your existing asset catalog. Set the target App Icon source to AppIcon. For a status item, use NSImage(named: "MenuBarIcon"), set isTemplate = true and size = NSSize(width: 18, height: 18).

These files use the classic macOS icon pipeline. They are not an Icon Composer layered .icon document. The vector master omits the subtle raster export shadows to keep it straightforward to edit. Review the installed icon in your app at actual Dock and menu bar sizes before release.
