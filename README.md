# Cubelyze

A local macOS application for reviewing Rubik's Cube solve videos.

Open a local video with the native file picker and review it with AVFoundation.
Includes a click-and-drag review timeline, frame stepping, playback speeds, and
elapsed/total time in milliseconds.
Requires macOS 14 or later. Built with Swift and SwiftUI; no third-party dependencies.

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

To build from the command line:

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

Licensed under the MIT License.
