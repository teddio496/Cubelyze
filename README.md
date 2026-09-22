# Cubelyze

A local macOS application for reviewing Rubik's Cube solve videos.

Open a local video with the native file picker and review it with AVFoundation.
Includes a click-and-drag review timeline, frame stepping, playback speeds,
elapsed/total time in milliseconds, and timestamped annotations.
Requires macOS 14 or later. Built with Swift and SwiftUI; no third-party dependencies.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools, including the Swift compiler and macOS SDK
- A macOS-supported `.mov` or `.mp4` video codec for testing

Xcode is optional. Install it if you want to open the project in Xcode, use the
Xcode debugger, or build with `xcodebuild`. The command-line build script works
with the standalone Xcode Command Line Tools:

```sh
xcode-select --install
```

There are no Swift Package Manager, CocoaPods, Homebrew, or other third-party
dependencies to install. The app currently has no automated test suite; the
build commands below are the available build checks.

## Run

Open `Cubelyze.xcodeproj` in Xcode, select the Cubelyze scheme and My Mac,
then press Run. Click **Open Video…** (⌘O) and choose a `.mov` or `.mp4` file
with a macOS-supported codec. Playback starts automatically; click **Pause** or
press Space to toggle playback.

- **Left/Right Arrow:** pause and step one video frame backward/forward.
- **Shift+Left/Right Arrow:** seek approximately one second backward/forward,
  keeping the current playing or paused state.
- **Speed:** choose 0.25×, 0.5×, 1×, or 2×. The selection also applies after pausing.
- **Timeline:** click to seek or drag to scrub. Playback pauses during scrubbing
  and resumes at the selected speed on release if it was playing beforehand.

The same controls are available below the video. Seeking stops at the beginning
or end of the video; pressing Play after playback ends starts it again.

## Annotations

Press a number key or click its **Events** button without pausing playback.
Press **Pause** once at its start and again at its end:

| Key | Category |
| --- | --- |
| 1 | Pause |
| 2 | Rotation |
| 3 | Regrip |
| 4 | Other |

Pause events appear as spans on a separate timeline lane; the other events appear
as point markers. All appear in the chronological annotation list.
Click a marker, span, or list entry to seek to its start; click its trash button to delete it.
Annotations are held in memory only and cleared when you open a video or quit.

## Solve segments

Press **Next Segment** or **Shift+N** at the start of Cross, then again just
after Cross is completed. Each press closes the current segment and immediately
starts the next: F2L #1–4, OLL, then PLL. Press once more after PLL and final
AUF to close the solve. Recognition, setup moves, pauses, and other transitions
remain inside the active segment. There are no transition segments or gaps.

The **Solve** button uses this boundary workflow. **Cancel** discards an
unfinished boundary. The list shows start, end, and duration. Click a segment
in the list or its timeline block to seek to its start. **Edit** moves its start
or end boundary and updates the neighboring segment at that shared timestamp;
it also changes the optional case label. Times are seconds. Deleting a segment
removes it and all later segments so the remaining sequence stays continuous.
Segment data is held in memory only.

## Build

If Xcode is installed, build from the command line with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Cubelyze.xcodeproj -scheme Cubelyze -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/Cubelyze.app
```

Alternatively, build using only the installed Swift Command Line Tools:

```sh
sh scripts/build.sh
open build/Cubelyze.app
```

To create a versioned ZIP for a GitHub release:

```sh
sh scripts/package-release.sh 0.1.0
```

The resulting archive is ad-hoc signed for development. Public binaries should
be signed with a Developer ID certificate and notarized by Apple before release;
otherwise macOS Gatekeeper may warn users.

## Current limitations

- macOS 14 or later is required.
- Video support is limited to codecs supported by AVFoundation on the user's Mac.
- There is no in-app export or sharing workflow yet.
- There is no automated test suite yet; builds and affected workflows must be
  verified manually.
- Release archives produced by the included script are not notarized.

## Contributing

Issues and focused pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for setup and verification guidance. Security issues should be reported according
to [SECURITY.md](SECURITY.md).

Licensed under the MIT License.
