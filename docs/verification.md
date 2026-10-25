# Verification

Verified for the 0.1.5 publication candidate on Apple Silicon, macOS 27.0.1.
No installed app, user document, permission, or login setting was changed.
The original latest source and its packaged app were preserved; that app's
binary SHA256 matched the installed Orbit before preparation.

## Processing

All **33 core checks passed** using real system encoders and installed ImageOptim
codecs. They cover PNG/JPG/WebP/AVIF/PDF output, pixel dimensions and channel
order, transparent JPEG backgrounds, all PDF pages, byte-preserving PDF copies,
EXIF orientation, lossless PNG pixels, animated GIF frames and timing, unchanged
originals, invalid inputs, batch rollback, missing tools, cancellation, timeout,
and temporary-folder cleanup. No visible codec window was observed for the
tested ImageOptim installation.

## Invocation and response

All **12 asynchronous Tab checks** and **8 response checks** passed. They cover
hold/release, Escape, empty or failed Finder replies, stale selection reads,
switching applications, early release with a chosen action, actual conversion,
and immediate presentation/dismissal callbacks. These are controlled harness
checks, not physical keyboard input or a desktop timing benchmark.

## Native interface

The native audit passed sector hit testing, the 236-point wheel, a 12-point
template icon, transparent ready/working center, six accessibility actions,
Tab/Enter/Escape, duplicate-action blocking, and long-message layout. All six
labels were visible in a cached native view hierarchy. Foreground drawing was
above the material. Progress was confined to the selected sector for all six actions.

Actual properties showed zero view borders, no shape-mask stroke, no outlined
buttons, and no assigned min/max layout dimensions. This verifies the inspected
native views; it is not a full VoiceOver or color-contrast certification.

The five-stage demo sends Tab-down, pointer hover over PNG, and Tab-up directly
to its own real controller and wheel. It produced a readable PNG, kept the PDF
byte-for-byte unchanged, and hid the wheel on completion. Its windows stayed
offscreen and the demo never became frontmost. No global input or personal
Finder selection was used. The file area and cursor are scripted demonstration
views. Offscreen captures do not verify live desktop vibrancy.

## Build and privacy

The portable developer build passes strict code-signature verification. It is
ad hoc signed, without Developer ID or notarization. Codec libraries are copied
from a configurable directory; originals are never modified. Public media is
stripped of device metadata before committing.

The exact source archive is reviewed independently from the working directory.
Build caches, local review reports, rollback apps, personal files, connectors,
skills, credentials, and machine-specific paths are excluded. The repository
is intentionally attributed to Egor Belyakov and uses a GitHub noreply address;
it is not an anonymous project.

## Not verified

- Physical Tab input against Finder in this preparation session.
- Earlier macOS releases, Intel Macs, or installation on another Mac.
- A full VoiceOver session or live desktop blur in the demonstration.
- Gatekeeper acceptance, Developer ID signing, or notarization.
- GitHub-hosted CI or a release before publication approval.

Run `zsh Tools/check.sh` after building. OPT tests need the installed ImageOptim
codecs. System codec services may be unavailable inside a restrictive sandbox.
