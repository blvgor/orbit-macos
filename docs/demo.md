# Demo capture

The five screenshots and animation show the actual 0.1.5 `WheelView` and
`AppController` in a task-owned native window. This is a scripted demonstration,
not a Finder screen recording. The neutral file area and pointer belong to the
capture harness. A blank `Demo.pdf` is generated for this demonstration.

1. The document is present, without selection or a wheel.
2. A pointer click is illustrated with a filled blue filename selection.
3. A Tab-down event is dispatched only to this controller. The real wheel appears
   around the document, with no extra center symbol.
4. A pointer event over PNG selects that sector while Tab remains held.
5. Tab-up runs the real converter. The readable PNG is saved beside the unchanged
   PDF. The controller dismisses the wheel; two files remain visible.

The video uses 240 freshly rendered offscreen native frames at 30 fps, lasting
8 seconds. The GIF uses the same frames with centisecond-rounded frame delays.
Pointer paths use smooth easing; brief selection, caption, and appearance fades
are presentation effects in the harness. The pauses make the steps readable;
they do not measure Finder response or conversion speed.
No global input is generated. The selection provider returns only the test PDF.

To reproduce after building:

```sh
zsh Tools/capture-demo.sh
```

This uses AppKit in a graphical macOS session. No screen recording permission
is needed: `cacheDisplay` captures only the harness's own view hierarchy. Its
windows stay offscreen, never become key or main, and never activate the demo application. No Finder is opened, personal files read, hot keys registered, login
items changed, or installed Orbit launched. The offscreen material is a neutral
preview; it does not reproduce live desktop blur.

Raw captures, fixtures, and the JSON verification report go to a fresh
`.build/demo.*` directory. Public PNGs are stripped of device profiles and metadata,
then tagged with standard sRGB. The animation can be assembled from these frames
with FFmpeg. Raw local reports are excluded from the source repository.
