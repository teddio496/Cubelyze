# Cubelyze

A local macOS application for reviewing Rubik's Cube solve videos.

Import a local video into the solve library and review it with AVFoundation.
Includes a click-and-drag review timeline, frame stepping, playback speeds,
elapsed/total time in milliseconds, and timestamped annotations.
Requires macOS 14 or later. Built with Swift and SwiftUI; no third-party dependencies.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools, including the Swift compiler and macOS SDK
- A macOS-supported `.mov` or `.mp4` video codec for testing

## Download and install

Download the latest `Cubelyze-*-macOS.dmg` from [GitHub Releases](https://github.com/teddio496/Cubelyze/releases). Open the DMG and drag Cubelyze to Applications. The ZIP is an alternative portable download. Cubelyze requires macOS 14 or later. Replace an older version by dragging the new app over it; uninstall by deleting Cubelyze from Applications. Your local solve data remains in `~/Library/Application Support/Cubelyze`.

GitHub downloads are ad-hoc signed and not Apple notarized. macOS may block the first launch; if you trust the download, use **System Settings → Privacy & Security → Open Anyway** after the blocked launch. Building from source is also supported below.

Xcode is optional. Install it if you want to open the project in Xcode, use the
Xcode debugger, or build with `xcodebuild`. The command-line build script works
with the standalone Xcode Command Line Tools:

```sh
xcode-select --install
```

There are no Swift Package Manager, CocoaPods, Homebrew, or other third-party
dependencies to install. The build commands below check the app; `sh scripts/test-phase-templates.sh`
checks phase progression and persistence compatibility. Run
`sh scripts/test-issue-tags.sh` for annotation tag checks.

## Run

Open `Cubelyze.xcodeproj` in Xcode, select the Cubelyze scheme and My Mac,
then press Run. Click **Import Video…** (⌘O), choose one or more `.mov` or `.mp4`
files, or drop video files onto the library. A single import opens its analyzer;
multiple imports remain in the library, grouped by recording day. Cubelyze uses
video creation metadata when available, then the file creation date, then the
import date. Importing the same file path again opens its existing solve instead
of creating another. Choose a video with a macOS-supported codec. Opening a solve restores its saved playhead and starts paused; click **Play** or
press Space to toggle playback.

- **Left/Right Arrow:** pause and step one video frame backward/forward.
- **Shift+Left/Right Arrow:** seek approximately one second backward/forward,
  keeping the current playing or paused state.
- **Speed:** choose 0.25×, 0.5×, 1×, or 2×. The selection also applies after pausing.
- **Timeline:** click to seek or drag to scrub. Playback pauses during scrubbing
  and resumes at the selected speed on release if it was playing beforehand.

The same controls are available below the video. Seeking stops at the beginning
or end of the video; pressing Play after playback ends starts it again.

The **Overlay** switch (or ⌘⇧H) shows the current phase and active Pause directly
on the video. Point events appear only while the playhead is near their timestamp.
The switch remembers its setting between launches and does not change the analysis.

## Review workspace

The video, timeline, and inspector use resizable split panes. Hide the inspector
with the toolbar sidebar button. Transport controls sit beneath the video;
phase and event marking controls sit above the timeline. The phase action names
its next step, and completion exposes Review Events and Next Solve.

Use **Compact / Expand**, **Fit Video**, **Fit Solve**, **Fit Selection**, and the
**− / +** timeline controls to manage space and zoom. The shared time ruler aligns
with all lanes; nearby point events are grouped by type and can be selected from
a count menu or **Event List**. The video has **Fit / − / +** controls; drag the
zoomed picture to pan around the cube.

Selected-event or phase details appear first in the inspector. **Solve Details**
contains the method and scramble. Phase boundaries and case labels are edited
inline; use playhead placement or frame adjustments to refine an edge. **⌘Z**
undoes annotation deletion, tag/note changes, and boundary edits. Deleting a phase
asks before removing it and all later phases.

The library includes thumbnails, per-solve timing and review status, search, and
status filters. Toolbar arrows navigate between solves without returning to the
library. The toolbar reports Saving / Saved; failures remain visible.

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

Select an event and choose **Add Tags…** in the inspector to attach one or more
structured issue tags. The searchable picker groups 30 built-in tags by Pause /
lookahead, Recognition / planning, F2L efficiency, Rotation / orientation, and
Execution. Tags relevant to the event and its phase appear first in each group.
Click a tag to toggle it, or search and press Return; use arrow keys in the list
and Return or Space to toggle the selected result. Remove a tag with its × button
in the inspector. Free-text notes remain available alongside tags. Tags autosave
with each solve and are preserved when trimming. Unavailable catalog entries
remain saved and can still be removed.

Hover or select a duration span to reveal its edge handles. Drag an edge to resize
the interval, or drag the span to move it without changing its duration. The
drag readout shows the updated times; edits are clamped to the video.
Select an event from its timeline marker/span or the annotation list to edit an
optional note or delete it. Each solve autosaves as human-readable JSON in
`~/Library/Application Support/Cubelyze/Solves` and appears in the library when
the app reopens. The JSON stores a security-scoped bookmark for persistent video
access. Imported videos are not modified unless you explicitly trim them after
segmentation. Existing files in the older
`Projects` directory are retained but are not automatically added to the library.

The inspector summarizes analyzed solve and phase durations, pause time,
pause count and longest pause, plus Rotation, Regrip, and Other counts. Click the
longest pause to select it and seek to its start.

The inspector has an optional editable scramble for the current solve. The library
shows the count, best time, and mean time of completed solves (those with every phase in their selected method
finished). If a video moves, use **Relink…** on its library row to choose the
video again; the solve's analysis stays intact.

## Solve segments

Choose **Solve method** in the inspector before marking boundaries. Standard
CFOP is the default; presets also support XCross, 2-look OLL, 2-look PLL, and
all combinations of these variants. The phase sequence appears below the picker.
XCross combines Cross and the first F2L pair into one phase; 2-look variants
split OLL or PLL into two timed steps. Each solve remembers its method.
Changing a method after marking boundaries asks for confirmation and clears
phase timings and case labels; annotations and the scramble are kept. Older
solve files load as Standard CFOP.


Press **Next Segment** or **Shift+N** at the start of the first phase, then again
after that phase is completed. Each press closes the current segment and immediately
starts the next phase in the selected method. For Standard CFOP, this is Cross,
F2L #1–4, OLL, then PLL. Press once more after the final phase and final
AUF to close the solve. Recognition, setup moves, pauses, and other transitions
remain inside the active segment. There are no transition segments or gaps.

The **Solve** button uses this boundary workflow. **Cancel** discards an
unfinished boundary. The list shows start, end, and duration. Click a segment
in the list or its timeline block to seek to its start. The inspector moves its start
or end boundary and updates the neighboring segment at that shared timestamp;
it also changes the optional case label. Times are seconds. Deleting a segment
removes it and all later segments so the remaining sequence stays continuous.
Hover the divider between two completed segments and drag it to adjust their
shared boundary. Both phase durations update together. To place an interval or
segment edge on an exact frame, step the video to that frame and use **Start ←
playhead** or **End ← playhead** in the inspector.

Once all phases in the selected method are segmented, **Trim Video…** can remove
footage before the first phase and after the final phase. It creates a smaller, app-managed copy and
shifts the analysis timestamps to match. Annotations outside the retained range
are removed; overlapping Pause annotations are clipped. The original remains on
disk for **Undo Trim** during the current app session. On normal quit (or on the
next launch after an interrupted session), Cubelyze deletes the original only
after checking that the saved solve uses the trimmed copy and no other solve
uses the original. Trimming temporarily requires space for both files; if the
export cannot save disk space, it is discarded and the original stays active.

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

To create a versioned development ZIP:

```sh
sh scripts/package-release.sh 0.1.0
```

The resulting archive is ad-hoc signed. The tagged release workflow builds with Xcode and uploads an ad-hoc signed DMG and ZIP to GitHub Releases. These artifacts are not Apple notarized.

## Current limitations

- macOS 14 or later is required.
- Video support is limited to codecs supported by AVFoundation on the user's Mac.
- Analyses autosave locally, but there is no in-app export or sharing workflow yet.
- Duplicate detection currently uses the resolved file path. Copies at a new path
  can be imported as separate solves.
- Phase progression, annotation tags, and persistence have automated checks; playback and affected
  UI workflows still require manual verification.
- Development archives produced by `package-release.sh` are not notarized.

## App icon

Cubelyze includes a custom cube-and-timeline icon in both Xcode and command-line
builds. Source artwork and regeneration instructions are in
[docs/design/app-icon.md](docs/design/app-icon.md).

## Contributing

Issues and focused pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for setup and verification guidance. Security issues should be reported according
to [SECURITY.md](SECURITY.md).

Licensed under the MIT License.

The analysis inspector uses Overview, Details, and Tags tabs. Overview emphasizes total solve time and grouped phase totals; select a phase or event for detailed edits. The header’s ellipsis menu holds import, solve navigation, inspector visibility, and trimming. Playback shortcuts are shown in tooltips. Phases use distinct Cross, F2L, OLL, and PLL colors, and shared boundaries have visible drag handles with live timing feedback.
