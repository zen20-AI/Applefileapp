# Applefileapp

A macOS menu bar utility that opens a radial "file ring" whenever you drag a file.
Drop the file on a petal to convert it or open a quick editor. Results are saved next
to the original and never overwrite it.

```
Page 001.pdf  ──JPG──▶  Page 001.jpg  ──Crop──▶  Page 001 Cropped.jpg  ──Add BG──▶  Page 001 Cropped With Background.png
```

## The ring

Start dragging any file from Finder or the Desktop and the ring fades in beside the pointer.

| Convert ring | Tools ring |
| --- | --- |
| PNG · WEBP · HEIC · JPG · AVIF · TIFF · BMP · PDF · DOCX | Compress · Metadata · Edit · Annotate · Add BG · Crop · Redact |

- **Hub:** shows the file size. Hold the dragged file over the hub for about half a second to switch between the Convert and Tools rings.
- Images open on the **Tools** ring. PDFs and documents open on **Convert**.
- Petals that can't handle the file are dimmed, such as the file's current format.
- **Menu bar → Open Files…** opens the same ring without dragging. You click the petals instead.

### Conversions

| From | To |
| --- | --- |
| Images | Any image format this Mac can encode, plus PDF |
| PDF | Images (one per page, rendered at 300 dpi) or DOCX (text) |
| DOCX / RTF / TXT / HTML | PDF (US Letter) or DOCX |

The encoders come from ImageIO, so the options depend on the macOS version. Stock macOS
reads WebP but can't write it, so the WEBP petal stays dimmed unless a WebP encoder is
available.

### Tools

| Tool | What it does | Output |
| --- | --- | --- |
| Compress | Re-encodes images (JPEG/HEIC) or optimizes PDF images; keeps it only if smaller | `… Compressed` |
| Metadata | Lists EXIF / GPS / TIFF data, warns about location, removes it all | `… Clean` |
| Edit | Brightness, contrast, saturation, exposure, rotate, flip | `… Edited` |
| Annotate | Pen and highlighter with colors and sizes | `… Annotated` |
| Add BG | Gradient, solid or image backdrop with padding, corners, shadow, ratio (Auto, 1:1, 16:9, 4:5) | `… With Background.png` |
| Crop | Drag handles, aspect presets (Free, 1:1, 16:9, 9:16, 4:3, 3:4), exact W × H in pixels | `… Cropped` |
| Redact | Draw boxes to black out or pixelate | `… Redacted` |

## Build & run

Requires macOS 14+ and Xcode 15+ (Swift 5.9).

```sh
swift run AppleFileApp          # run from the terminal
swift test                      # core unit tests
scripts/build-app.sh            # creates build/Apple File App.app
```

You can also open `Package.swift` in Xcode and run the `AppleFileApp` scheme.

The app watches drags with a global mouse monitor. This doesn't need the Accessibility
permission because it never reads keystrokes.

## Layout

```
Sources/FileAppCore/     conversion, compression and image processing (no UI); unit tested
Sources/AppleFileApp/
  App/                   entry point, drag detection, action routing
  Ring/                  the radial menu panel, its model and drop handling
  Editors/               Crop, Add BG, Edit, Annotate, Redact, Metadata windows
  UI/                    theme, shared controls, progress toast
Tests/FileAppCoreTests/
```
