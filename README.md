# Orbit

A file conversion wheel for macOS. Select an image or PDF, hold Tab,
and choose a format. Orbit saves a new file next to the original.

[Русская инструкция](README.ru.md) · [How it works](docs/architecture.md) · [MIT](LICENSE)

![Hold Tab to open Orbit around a selected document](docs/media/03-hold-tab.png)

Version **0.1.5**, an early local utility. The interface is in Russian.

[Watch the walkthrough](docs/media/orbit-demo-30fps.mp4) · [GIF](docs/media/orbit-demo-30fps.gif).
The screenshot uses an isolated native test window; [capture details](docs/demo.md).

## Why

A quick conversion should not require opening an editor, exporting, and finding
the source folder again. Orbit keeps the action near the file. It runs in the
menu bar, without a Dock icon or a startup window.

## Actions

| Sector | Result |
| --- | --- |
| PNG | A PNG image |
| JPG | JPEG at quality 0.9; transparent areas become white |
| WEBP | WebP at quality 90, using bundled libwebp |
| AVIF | AVIF, if the running macOS provides the encoder |
| PDF | An image in a PDF; PDF → PDF makes a byte-preserving copy |
| OPT | Lossless optimization of PNG, JPEG, or GIF using installed ImageOptim tools |

PDF-to-image exports every page at 144 dpi. Multiple files are supported.
Existing files are not overwritten: conflicting names get a number, and
optimized copies get an `-optimized` suffix.

Processing is local. Orbit has no network client, account, upload service, or analytics.

## Requirements

- An Apple Silicon Mac.
- macOS 14+ is the build target. Verification was performed on macOS 27.0.1;
  earlier versions have not been tested. AVIF depends on the system encoder.
- To build: Apple Command Line Tools with a Swift 6 compiler, and libwebp.
- For **OPT only**: [ImageOptim](https://imageoptim.com/mac) installed at
  `/Applications/ImageOptim.app`, containing `oxipng`, `jpegoptim`, and `gifsicle`.
  The other actions work without ImageOptim.

Python, FFmpeg, and a web server are not runtime requirements.

## Build and install

Install Apple's Command Line Tools if needed:

```sh
xcode-select --install
```

With [Homebrew](https://brew.sh/) already installed, run from the repository:

```sh
brew install webp
zsh build.sh
```

Move `dist/Orbit.app` into Applications and open it. Look for the small wheel in
the menu bar. The build does not install or launch the app.

For another compatible codec installation, set `ORBIT_WEBP_LIB_DIR` to the
directory containing `libwebp.7.dylib` and `libsharpyuv.0.dylib`. The build copies
these libraries without modifying them.

This developer build is ad hoc signed, without Developer ID or notarization.
macOS may require approval in **System Settings → Privacy & Security**. There is
currently no notarized installer.

## Use

1. Click an image or PDF in Finder to select it.
2. Keep the pointer over the file and **hold Tab**. The wheel opens around the pointer.
3. Move to a format and **release Tab**. Orbit converts the selected file and saves
   the result beside it. The wheel closes immediately after a successful save.

Release Tab without choosing a sector to dismiss. You can also click a sector.
Arrow keys select PNG / WEBP / OPT / JPG (up / right / down / left); Escape cancels.
In the manual file-picker mode, Tab / Shift + Tab move between sectors and
Enter or Space runs the selected action.

| 1. Document | 2. Click | 3. Hold Tab | 4. Choose PNG | 5. Saved |
| --- | --- | --- | --- | --- |
| ![Document](docs/media/01-document.png) | ![Selected file](docs/media/02-selected.png) | ![Tab held](docs/media/03-hold-tab.png) | ![PNG selected](docs/media/04-choose-png.png) | ![Two files, wheel closed](docs/media/05-complete.png) |

Alternatively, click the menu bar icon and **«Выбрать файл…»** (Choose file).
This route supports multiple files and does not need the Finder gesture.
**«Показать результат»** reveals the latest output in Finder.

## Permissions and startup

Tab uses a registered macOS hot key scoped to Finder. It does not require
Accessibility or Input Monitoring permission. Reading Finder's selected files may
request **Automation → Finder** permission in System Settings → Privacy & Security.
Orbit observes pointer events while running; it does not record keystrokes.
The manual file picker works without reading Finder's selection.

On its first normal launch, Orbit requests registration as a login item.
**«Автозапуск»** shows its state and lets you disable it. macOS may require
confirmation in **System Settings → General → Login Items**. Rebuilding or moving
the app may require granting permissions again.

## File behavior and limits

- Work is staged beside the input. A handled batch failure rolls back its new
  outputs and removes temporary work. A forced kill or system crash may leave
  an `.orbit-task-*` folder. This is not a crash-proof filesystem transaction.
- OPT uses ImageOptim's individual codecs, not its full GUI pipeline or your
  preferences. It does not launch ImageOptim's window.
- OPT drops text metadata from PNG but retains selected color, orientation, and
  animation chunks. JPEG metadata is preserved. OPT is not a metadata privacy tool.
- Conversion renders pixels and does not preserve all metadata or color profiles.
  JPG and WebP are lossy. PDF-to-image rasterizes pages; no OCR is performed.
- Animated inputs are rejected for conversion to avoid losing frames. Animated
  GIF optimization is supported through OPT.
- Encrypted PDFs, folders, text, Office documents, and video are unsupported.
- Processing is limited to 100 million pixels per image or PDF page set.
  WebP has a separate limit of 16,383 pixels per side.
- Fill is an activity indicator, not a measured percentage. It reaches completion
  only after successful processing, validation, and saving.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No Dock icon | Expected; use the menu bar wheel |
| Tab does nothing | Select a file in Finder, check Finder Automation, or use «Выбрать файл…» |
| OPT reports a missing tool | Check ImageOptim's installation and required codecs |
| AVIF cannot be saved | Choose another format; the system encoder may be unavailable |
| OPT does not shrink the file | The input may already be optimized; a larger result is replaced with a copy of the input |
| Saving fails | The input folder must be writable |

To uninstall, disable **«Автозапуск»**, choose **«Завершить Orbit»**, then remove
Orbit from Applications. Your generated files stay in their folders.

## Development

```sh
zsh build.sh
zsh Tools/check.sh
```

Core checks use real encoders and ImageOptim tools: conversions, PDF pages,
orientation, animation, original preservation, rollback, cancellation, and timeout.
The native audit covers geometry, keyboard actions, accessibility elements, and
view/layer properties. Async gesture and response checks cover Tab hold/release,
selection races, cancellation, and immediate dismissal. They do not send global input.

[Architecture](docs/architecture.md) · [Verification](docs/verification.md) · [Demo capture](docs/demo.md)

## License

Orbit's original code is [MIT licensed](LICENSE), © 2026 Egor Belyakov.
WebP libraries retain their BSD license and patent grant. ImageOptim is installed
separately and retains its own licensing. See [third-party notices](THIRD_PARTY_NOTICES.md).
