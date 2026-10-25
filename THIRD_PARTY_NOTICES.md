# Third-party components

Orbit's original source code is MIT licensed: see [LICENSE](LICENSE). This does
not replace the licenses of the components below.

## libwebp and libsharpyuv

The build copies `libwebp.7.dylib` and `libsharpyuv.0.dylib` from a local libwebp
installation into the app bundle. No codec binaries are committed to the repository.

- Project: [WebM libwebp](https://chromium.googlesource.com/webm/libwebp/).
- Copyright: Google Inc. and the libwebp contributors, as stated upstream.
- BSD 3-Clause: [full notice](docs/licenses/libwebp-COPYING).
- [Additional patent grant](docs/licenses/libwebp-PATENTS).
- These notices come from upstream tag `v1.6.0`. If you substitute another version
  or a modified build, check and preserve its applicable notices.

The build includes these notices in `Orbit.app/Contents/Resources`.

## ImageOptim and its command-line tools

OPT executes `oxipng`, `jpegoptim`, and `gifsicle` from a separately installed
`/Applications/ImageOptim.app`. Orbit does not bundle or redistribute ImageOptim
or these tools, link to its GPL framework, launch its GUI, or use its online service.
These projects retain their own licenses. Orbit does not install them.

- [ImageOptim](https://imageoptim.com/mac)
- [oxipng](https://github.com/oxipng/oxipng)
- [jpegoptim](https://github.com/tjko/jpegoptim)
- [gifsicle](https://www.lcdf.org/gifsicle/)

The internal ImageOptim tools directory is an implementation detail, not a stable
public API. An ImageOptim update may require an Orbit update.

## Apple frameworks

AppKit, Core Graphics, ImageIO, ApplicationServices, and ServiceManagement are
supplied by macOS. They are not redistributed in this repository.
