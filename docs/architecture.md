# How Orbit works

Orbit is a native Swift/AppKit accessory application, without Electron or a web server.

| File | Responsibility |
| --- | --- |
| `Sources/main.swift` | App entry point and offscreen audit mode |
| `Sources/RegisteredHotKey.swift` | Finder-scoped Tab registration and dispatch |
| `Sources/Application.swift` | Menu bar, Finder gesture, permissions, login item, jobs |
| `Sources/WheelView.swift` | Pointer, keyboard, drag input, accessible sectors, rendering |
| `Sources/WheelGeometry.swift` | Geometry, hit testing, template icon |
| `Sources/Processing.swift` | Processing actor, codecs, staging, validation, rollback |
| `Sources/NativeVerification.swift` | Offscreen rendering and native property audit |
| `Tests/CoreChecks.swift` | Generated fixtures and real encoder/optimizer checks |

The 236-point wheel uses `NSVisualEffectView` with the HUD material and a
six-sector mask. Focus and selection use fills. Six accessibility actions are
exposed. The menu bar icon is an 12-point template image.

`RegisteredHotKey.swift` registers Tab only while Finder is frontmost. Holding
Tab presents the wheel immediately, while Finder's selection is read asynchronously
through AppleScript. Hover chooses a sector; releasing Tab commits it. Late replies
are ignored after cancellation or a new gesture. The file picker is an alternative.
This hot key does not require Accessibility or Input Monitoring permissions. Orbit
does not generate global pointer or keyboard input.

The UI stays on the main actor. A `FileProcessor` actor serializes file work.
Jobs stage data in UUID-named folders beside the input, validate results, and
move them to unused names. Handled errors and cancellation roll back the job's
outputs. This is not a crash-proof filesystem transaction.

ImageIO decodes inputs and writes PNG, JPEG, and available AVIF. Core Graphics
handles PDFs. WebP uses a C API loaded from bundled libwebp. OPT runs the
separately installed ImageOptim codecs on copies. Cancellation and the
five-minute optimizer timeout terminate only the job's own child process.

The progress fill indicates activity. It cannot report a reliable codec percentage;
it completes only after validation and saving succeed.

Build products, generated test files, and local review data are excluded from the
source repository. Building does not launch Orbit or change system settings.
