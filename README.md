# Petal

**Petal** is a macOS menu bar utility that opens a radial "file ring" whenever you drag a file.
Drop the file on a petal to convert it or open a quick editor. A Manager window handles
batches, history and settings. Results are saved as new files and never overwrite the original.

```
Page 001.pdf  ──JPG──▶  Page 001.jpg  ──Crop──▶  Page 001 Cropped.jpg  ──Add BG──▶  Page 001 Cropped With Background.png
```

## The ring

Start dragging any file from Finder or the Desktop and the ring fades in beside the pointer.

| Convert ring | Tools ring |
| --- | --- |
| PNG · WEBP · HEIC · JPG · AVIF · TIFF · BMP · PDF · DOCX | Compress · Resize · Metadata · Edit · Annotate · Add BG · Crop · Redact · Merge PDF · Pages · Split PDF |

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
| Resize | Scales every image by a percentage or to fit a maximum side (never upscales when fitting) | `… Resized` |
| Metadata | Lists EXIF / GPS / TIFF data, warns about location, removes it all | `… Clean` |
| Edit | Brightness, contrast, saturation, exposure, rotate, flip | `… Edited` |
| Annotate | Pen and highlighter with colors and sizes | `… Annotated` |
| Add BG | Gradient, solid or image backdrop with padding, corners, shadow, ratio (Auto, 1:1, 16:9, 4:5) | `… With Background.png` |
| Crop | Drag handles, aspect presets (Free, 1:1, 16:9, 9:16, 4:3, 3:4), exact W × H in pixels | `… Cropped` |
| Redact | Draw boxes to black out or pixelate | `… Redacted` |
| Merge PDF | Combines two or more images and PDFs, in order, into one PDF | `… Merged.pdf` |
| Pages | Page grid: drag to reorder, rotate, delete, add pages from other PDFs or images, extract the selection (⌘A, ⌫, ⌘[ / ⌘], ⌘S) | `… Edited.pdf`, `… Extract.pdf` |
| Split PDF | Every page, every N pages, or ranges like `1-3, 5, 8-` | `… Split/… Pages 1-3.pdf` |

## Control panel

Click the petal icon in the menu bar for a Control Center–style panel: pause or resume the
drag ring, drop files to bloom the ring right there, jump to Workspace / History / Settings,
and drag recent results straight into other apps.

## Manager

Open it from the menu bar (**Open Manager**, ⌘M), by clicking the Dock icon, or by opening
files with the app from Finder (**Open With → Petal**).

- **Workspace:** drop files or whole folders, then Convert, Compress, Resize, Remove Metadata
  (in bulk), open an editor or the ring. The **PDF** menu merges files (in list order), opens
  the page organizer, or splits PDFs into single pages. Drag rows or use **Sort** to set the
  order; right-click for Organize Pages, Split, or Move to Trash. Actions apply to the
  selection, or to every file when nothing is selected.
- **History:** every result, searchable, with Open / Reveal, "Add results to Workspace",
  and clean-up of entries whose files are gone.
- **Settings:** launch at login, Dock icon, reveal in Finder after saving, ring on/off and
  drag distance, save next to the original or into a chosen folder, JPG/HEIC and compression
  quality, PDF render resolution.

## Install

Open `Petal-<version>.dmg` and drag **Petal** onto **Applications**.
The build is ad-hoc signed, not notarized, so the first time macOS blocks it:
Control-click the app → **Open** → **Open** (or System Settings → Privacy & Security →
**Open Anyway**).

## Build & run

Requires macOS 14+ and Xcode 16+ or the Command Line Tools (Swift 6 toolchain).

```sh
swift run Petal          # run from the terminal
swift test                      # core unit tests (Swift Testing)
scripts/build-app.sh            # creates build/Petal.app (with icon)
scripts/build-dmg.sh            # creates build/Petal-1.0.0.dmg
UNIVERSAL=1 VERSION=1.1.0 scripts/build-dmg.sh   # Apple silicon + Intel
```

Set `SIGN_IDENTITY="Developer ID Application: …"` to sign with a real certificate, and
`NOTARY_PROFILE=…` to notarize (see the top of `scripts/build-dmg.sh`).

## Updates (Sparkle)

Petal checks for updates daily and from **Settings → Updates** or **Updates** in the control
panel. The feed is
`https://github.com/zen20-AI/petal-releases/releases/latest/download/appcast.xml`, so
releases go to a separate **public** repo (`zen20-AI/petal-releases`); override with
`FEED_URL=…`, or `FEED_URL=` to build without updates.

Updates are signed with an EdDSA key. The public key is in `scripts/build-app.sh`; the
private key is in the login keychain of the Mac that created it (account `petal`). Back it
up — without it you can't ship updates to existing installs:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account petal -x petal-private-key   # export
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account petal -f petal-private-key   # import elsewhere
```

To ship a version: write `release-notes/<version>.md`, commit (the build number is the
commit count), then

```sh
VERSION=1.1.0 scripts/release.sh             # build, sign, update appcast.xml
VERSION=1.1.0 PUBLISH=1 scripts/release.sh   # …and create the GitHub release
```

and commit the updated `appcast.xml`.

With only the Command Line Tools, the macOS 27 SDK can't compile the app (SwiftUI's
`@State` macro plugin ships with Xcode), so `build-app.sh` builds against an older
installed SDK. To do the same by hand, prefix commands with
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`. For tests with only the
Command Line Tools, use a separate build folder so the two SDKs don't mix, and run
`swift test --scratch-path .build/tests` (the app target fails but the test bundle still
builds), then `swift test --scratch-path .build/tests --skip-build`.

You can also open `Package.swift` in Xcode and run the `Petal` scheme.

The app watches drags with a global mouse monitor. This doesn't need the Accessibility
permission because it never reads keystrokes.

## Layout

```
Sources/FileAppCore/     conversion, compression and image processing (no UI); unit tested
Sources/Petal/
  App/                   entry point, menu bar, drag detection, settings, action routing
  Manager/               Manager window: workspace, history, settings, about
  Ring/                  the radial menu panel, its model and drop handling
  Editors/               Crop, Add BG, Edit, Annotate, Redact, Resize, Metadata windows
  UI/                    theme, shared controls, progress toast
Tests/FileAppCoreTests/
scripts/                 build-app.sh, build-dmg.sh, release.sh, make-icon.swift
release-notes/           notes shown in the update dialog
appcast.xml              Sparkle update feed
```
