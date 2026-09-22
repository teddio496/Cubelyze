# Cubelyze

A local macOS application for reviewing Rubik's Cube solve videos.

This initial milestone opens a local video with the native file picker and plays
it with AVFoundation. It includes play/pause and elapsed/total playback time.
Requires macOS 14 or later. Built with Swift and SwiftUI; no third-party dependencies.

## Run

Open `Cubelyze.xcodeproj` in Xcode, select the Cubelyze scheme and My Mac,
then press Run. Click **Open Video…** (⌘O) and choose a `.mov` or `.mp4` file
with a macOS-supported codec. Playback starts automatically; click **Pause** or
press Space to toggle playback.

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
