import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackModel()
    @State private var confirmsTrim = false
    private let refreshTimer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if playback.selectedSolveID == nil {
                SolveLibrary(playback: playback)
            } else {
                analyzer
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onReceive(refreshTimer) { _ in playback.refresh() }
        .onDisappear { playback.player.pause() }
    }

    private var analyzer: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Library") { playback.showLibrary() }
                Button("Import Video…", action: playback.chooseVideo)
                    .keyboardShortcut("o")
                Text(playback.filename ?? "Choose a local video to begin")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if playback.isTrimming {
                    ProgressView().controlSize(.small)
                    Text("Trimming…").font(.caption)
                } else if playback.canUndoTrim {
                    Button("Undo Trim") { playback.undoTrim() }
                } else if playback.trimRange != nil {
                    Button("Trim Video…") { confirmsTrim = true }
                }
                Toggle("Overlay", isOn: $playback.showsAnalysisOverlay)
                    .toggleStyle(.switch)
                    .fixedSize()
                    .help("Show analysis overlay (⌘⇧H)")
            }
            GeometryReader { workspace in
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        AnalysisVideoView(playback: playback)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                        ReviewTimeline(playback: playback)
                            .frame(height: 270)
                        ControlBar(playback: playback)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    AnalysisInspector(playback: playback)
                        .frame(width: min(310, workspace.size.width * 0.28))
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            if let message = playback.errorMessage ?? playback.saveMessage ?? playback.annotationMessage ?? playback.segmentMessage {
                Text(message).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let solve = playback.selectedSolve, !playback.videoExists(for: solve) {
                Button("Relink Video…") { playback.relinkVideo(for: solve) }
            }
        }
        .padding()
        .disabled(playback.isTrimming)
        .confirmationDialog("Trim video to the completed solve?", isPresented: $confirmsTrim) {
            Button("Trim Video") { Task { await playback.trimCompletedSolve() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Video before Cross and after PLL will be removed from the active copy. The original stays available for Undo until you quit Cubelyze, then is permanently deleted. Annotations outside the solve will also be removed.")
        }
    }
}

private struct SolveLibrary: View {
    @ObservedObject var playback: PlaybackModel

    private var days: [Date] {
        Array(Set(playback.solves.map { Calendar.current.startOfDay(for: $0.recordedAt) }))
            .sorted(by: >)
    }

    private var completed: [Double] { playback.completedSolveDurations }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Solve Library").font(.largeTitle).fontWeight(.semibold)
                Spacer()
                Button("Import Video…", action: playback.chooseVideo)
                    .keyboardShortcut("o")
            }
            if let message = playback.errorMessage ?? playback.saveMessage {
                Text(message).foregroundStyle(.red)
            }
            if let message = playback.importMessage { Text(message).foregroundStyle(.secondary) }
            HStack(spacing: 24) {
                Text("\(playback.solves.count) solves")
                Text("\(completed.count) complete")
                if let best = completed.min() {
                    Text("Best \(PlaybackModel.timestamp(best))")
                    Text("Average \(PlaybackModel.timestamp(completed.reduce(0, +) / Double(completed.count)))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if playback.solves.isEmpty {
                ContentUnavailableView("No solves yet", systemImage: "video",
                                       description: Text("Import a video to start analyzing a solve."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(days, id: \.self) { day in
                        Section(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())) {
                            ForEach(playback.solves.filter {
                                Calendar.current.isDate($0.recordedAt, inSameDayAs: day)
                            }) { solve in
                                HStack {
                                    Button { playback.openSolve(solve) } label: {
                                        HStack {
                                            Text(solve.recordedAt.formatted(date: .omitted, time: .shortened))
                                                .monospacedDigit()
                                            Text(solve.filename).lineLimit(1)
                                            Spacer()
                                            if !playback.videoExists(for: solve) {
                                                Label("Video missing", systemImage: "exclamationmark.triangle")
                                                    .foregroundStyle(.secondary)
                                            }
                                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    if !playback.videoExists(for: solve) {
                                        Button("Relink…") { playback.relinkVideo(for: solve) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task { await playback.importVideos(files) }
            return true
        }
    }
}

private struct AnalysisVideoView: View {
    @ObservedObject var playback: PlaybackModel

    var body: some View {
        GeometryReader { geometry in
            let videoWidth = min(geometry.size.width,
                                 geometry.size.height * playback.videoAspectRatio)
            let videoHeight = videoWidth / playback.videoAspectRatio
            ZStack {
                PlayerView(playback: playback)
                if playback.showsAnalysisOverlay && playback.isReady {
                    AnalysisOverlay(playback: playback)
                        .frame(maxWidth: min(240, videoWidth * 0.4), alignment: .leading)
                        .padding(12)
                        .frame(width: videoWidth, height: videoHeight, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct AnalysisOverlay: View {
    @ObservedObject var playback: PlaybackModel

    private var hasContent: Bool {
        playback.overlaySegmentType != nil || !playback.overlayIntervals.isEmpty ||
        (playback.pendingAnnotation.map { $0.start <= playback.overlayTime } ?? false) ||
        !playback.overlayPointEvents.isEmpty
    }

    var body: some View {
        Group {
            if hasContent {
                VStack(alignment: .leading, spacing: 5) {
                    if let phase = playback.overlaySegmentType {
                        Text(phase.title).font(.headline)
                    }
                    ForEach(playback.overlayIntervals) { annotation in
                        eventLine(annotation.category,
                                  elapsed: playback.overlayTime - annotation.timing.start)
                    }
                    if let pending = playback.pendingAnnotation,
                       pending.start <= playback.overlayTime {
                        eventLine(pending.category,
                                  elapsed: playback.overlayTime - pending.start)
                    }
                    ForEach(playback.overlayPointEvents) { annotation in
                        eventLine(annotation.category, elapsed: nil)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                }
                .shadow(radius: 5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func eventLine(_ category: AnnotationCategory, elapsed: Double?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(category.color).frame(width: 6, height: 6)
            Text(category.title)
            if let elapsed {
                Text("· \(elapsed, specifier: "%.2f")s")
                    .monospacedDigit()
            }
        }
        .font(.caption)
    }
}

private struct SegmentEditor: View {
    @ObservedObject var playback: PlaybackModel
    let segment: SolveSegment
    @Environment(\.dismiss) private var dismiss
    @State private var startText: String
    @State private var endText: String
    @State private var caseLabel: String
    @State private var error: String?

    init(playback: PlaybackModel, segment: SolveSegment) {
        self.playback = playback
        self.segment = segment
        _startText = State(initialValue: String(format: "%.3f", segment.start))
        _endText = State(initialValue: String(format: "%.3f", segment.end))
        _caseLabel = State(initialValue: segment.caseLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(segment.type.title)")
                .font(.headline)
            Text("Type follows the Cross → F2L → OLL → PLL sequence.")
                .foregroundStyle(.secondary)
            HStack {
                Text("Start (seconds)")
                TextField("Start", text: $startText)
            }
            HStack {
                Text("End (seconds)")
                TextField("End", text: $endText)
            }
            TextField("Case label (optional)", text: $caseLabel)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    guard let start = Double(startText), let end = Double(endText),
                          playback.updateSegment(segment, start: start, end: end, caseLabel: caseLabel) else {
                        error = "Use times within the video that keep this and neighboring segments positive in duration."
                        return
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

private struct AnalysisInspector: View {
    @ObservedObject var playback: PlaybackModel
    @State private var editingSegment: SolveSegment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Inspector").font(.headline)
                    Spacer()
                    if playback.selectedAnnotation != nil || playback.selectedSegment != nil {
                        Button("Done") { playback.clearSelection() }
                            .buttonStyle(.borderless)
                    }
                }
                Divider()
                if playback.selectedSolve != nil {
                    Text("Scramble").font(.caption).foregroundStyle(.secondary)
                    TextField("Optional scramble", text: Binding(
                        get: { playback.selectedSolve?.scramble ?? "" },
                        set: playback.updateScramble
                    ), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    Divider()
                }
                if let annotation = playback.selectedAnnotation {
                    EventDetails(playback: playback, annotation: annotation)
                } else if let segment = playback.selectedSegment {
                    SegmentDetails(playback: playback, segment: segment,
                                   edit: { editingSegment = segment })
                } else {
                    StatisticsDetails(playback: playback)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditor(playback: playback, segment: segment)
        }
    }
}

private struct EventDetails: View {
    @ObservedObject var playback: PlaybackModel
    let annotation: VideoAnnotation

    private var note: Binding<String> {
        Binding(get: { playback.annotations.first(where: { $0.id == annotation.id })?.note ?? "" },
                set: { playback.updateAnnotationNote(id: annotation.id, note: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(annotation.category.title, systemImage: annotation.timing.end == nil ? "bookmark.fill" : "pause.fill")
                .font(.title3).fontWeight(.semibold).foregroundStyle(annotation.category.color)
            if let end = annotation.timing.end {
                InspectorValue(label: "Start", value: PlaybackModel.timestamp(annotation.timing.start))
                InspectorValue(label: "End", value: PlaybackModel.timestamp(end))
                InspectorValue(label: "Duration", value: PlaybackModel.timestamp(end - annotation.timing.start))
            } else {
                InspectorValue(label: "Time", value: PlaybackModel.timestamp(annotation.timing.start))
            }
            Text("Note").font(.caption).foregroundStyle(.secondary)
            TextField("Optional note", text: note, axis: .vertical)
                .lineLimit(3...6).textFieldStyle(.roundedBorder)
            Button("Delete Event", role: .destructive) { playback.deleteAnnotation(annotation) }
        }
    }
}

private struct SegmentDetails: View {
    @ObservedObject var playback: PlaybackModel
    let segment: SolveSegment
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(segment.type.title, systemImage: "square.split.2x1")
                .font(.title3).fontWeight(.semibold)
            InspectorValue(label: "Start", value: PlaybackModel.timestamp(segment.start))
            InspectorValue(label: "End", value: PlaybackModel.timestamp(segment.end))
            InspectorValue(label: "Duration", value: PlaybackModel.timestamp(segment.duration))
            if !segment.caseLabel.isEmpty { InspectorValue(label: "Case", value: segment.caseLabel) }
            HStack {
                Button("Edit", action: edit)
                Button("Delete", role: .destructive) { playback.deleteSegment(segment) }
            }
        }
    }
}

private struct StatisticsDetails: View {
    @ObservedObject var playback: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Solve Summary").font(.title3).fontWeight(.semibold)
            InspectorValue(label: "Total solve", value: PlaybackModel.timestamp(playback.analyzedDuration))
            if !playback.segments.isEmpty {
                Text("Phases").font(.caption).foregroundStyle(.secondary)
                ForEach(playback.segments) { segment in
                    Button { playback.selectSegment(segment) } label: {
                        InspectorValue(label: segment.type.title, value: PlaybackModel.timestamp(segment.duration))
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            InspectorValue(label: "Total pause", value: PlaybackModel.timestamp(playback.totalPauseTime))
            InspectorValue(label: "Pauses", value: "\(playback.pauseAnnotations.count)")
            if let pause = playback.longestPause {
                Button { playback.selectAnnotation(pause) } label: {
                    InspectorValue(label: "Longest pause", value: PlaybackModel.timestamp(pause.timing.duration ?? 0))
                }.buttonStyle(.plain)
            }
            InspectorValue(label: "Rotations", value: "\(playback.eventCount(.rotation))")
            InspectorValue(label: "Regrips", value: "\(playback.eventCount(.regrip))")
            InspectorValue(label: "Other", value: "\(playback.eventCount(.other))")
        }
    }
}

private struct InspectorValue: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
}

private struct ControlBar: View {
    @ObservedObject var playback: PlaybackModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(playback.isPlaying ? "Pause  Space" : "Play  Space", action: playback.togglePlayback)
                    Button("−1s  ⇧←") { playback.seek(by: -1) }
                    Button("◀︎  ←") { playback.stepFrame(by: -1) }
                    Button("▶︎  →") { playback.stepFrame(by: 1) }
                    Button("+1s  ⇧→") { playback.seek(by: 1) }
                    Divider().frame(height: 22)
                    ForEach(AnnotationCategory.allCases, id: \.self) { category in
                        Button("\(category.rawValue) \(category.title)") { playback.addAnnotation(category) }
                            .tint(category.color)
                            .opacity(playback.pendingAnnotation?.category == category ? 0.65 : 1)
                    }
                    Button("Next  ⇧N") { playback.markNextSegmentBoundary() }
                    Picker("Speed", selection: Binding(get: { playback.speed }, set: playback.setSpeed)) {
                        Text("0.25×").tag(Float(0.25))
                        Text("0.5×").tag(Float(0.5))
                        Text("1×").tag(Float(1))
                        Text("2×").tag(Float(2))
                    }.labelsHidden().fixedSize()
                }
            }
            if let pending = playback.pendingAnnotation {
                HStack {
                    Text("\(pending.category.title) started at \(PlaybackModel.timestamp(pending.start)); press \(pending.category.rawValue) to finish.")
                    Button("Cancel") { playback.cancelPendingAnnotation() }.buttonStyle(.borderless)
                }.font(.caption)
            } else if let pending = playback.pendingSegment {
                HStack {
                    Text("\(pending.type.title) started at \(PlaybackModel.timestamp(pending.start)); press Shift+N to finish.")
                    Button("Cancel") { playback.cancelPendingSegment() }.buttonStyle(.borderless)
                }.font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!playback.isReady)
    }
}

private struct ReviewTimeline: View {
    @ObservedObject var playback: PlaybackModel

    private var displayedPosition: Double { playback.scrubPosition ?? playback.position }

    private func x(_ time: Double, width: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return width * min(1, max(0, time / playback.duration))
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Solve segments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(playback.segments) { segment in
                            let blockWidth = max(2, x(segment.end, width: width) - x(segment.start, width: width))
                            Button {
                                playback.selectSegment(segment)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if blockWidth >= 48 { Text(segment.type.title).fontWeight(.medium) }
                                    if blockWidth >= 105 {
                                        Text(PlaybackModel.timestamp(segment.duration))
                                            .monospacedDigit()
                                    }
                                }
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .frame(width: blockWidth, height: 42, alignment: .leading)
                                .background(Color.blue.opacity(playback.selectedSegmentID == segment.id ? 0.38 : 0.18))
                                .overlay(alignment: .leading) { Rectangle().fill(Color.blue).frame(width: 1) }
                            }
                            .buttonStyle(.plain)
                            .help("\(segment.type.title): \(PlaybackModel.timestamp(segment.start))–\(PlaybackModel.timestamp(segment.end))")
                            .accessibilityLabel("\(segment.type.title), \(PlaybackModel.timestamp(segment.duration)); seek to start")
                            .offset(x: x(segment.start, width: width))
                        }
                        if let pending = playback.pendingSegment, displayedPosition > pending.start {
                            Text(pending.type.title)
                                .font(.caption)
                                .padding(.horizontal, 5)
                                .frame(width: max(2, x(displayedPosition, width: width) - x(pending.start, width: width)), height: 42, alignment: .leading)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .offset(x: x(pending.start, width: width))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: width, height: 42)

                    Text("Duration annotations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(playback.annotations) { annotation in
                            if let end = annotation.timing.end {
                                let spanWidth = max(3, x(end, width: width) - x(annotation.timing.start, width: width))
                                Button {
                                    playback.selectAnnotation(annotation)
                                } label: {
                                    Text(spanWidth >= 75 ? annotation.category.title : "")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 3)
                                        .frame(width: spanWidth, height: 26, alignment: .leading)
                                        .background(annotation.category.color.opacity(0.55))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(annotation.category.color)
                                .overlay {
                                    if playback.selectedAnnotationID == annotation.id {
                                        RoundedRectangle(cornerRadius: 3).stroke(.primary, lineWidth: 2)
                                    }
                                }
                                .help("\(annotation.category.title): \(PlaybackModel.timestamp(annotation.timing.start))–\(PlaybackModel.timestamp(end))")
                                .offset(x: x(annotation.timing.start, width: width))
                            }
                        }
                    }
                    .frame(width: width, height: 38)

                    Text("Point events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(playback.annotations) { annotation in
                            if annotation.timing.end == nil {
                                Button {
                                    playback.selectAnnotation(annotation)
                                } label: {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 12))
                                        .frame(width: 16, height: 38)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(annotation.category.color)
                                .background(playback.selectedAnnotationID == annotation.id ? Color.primary.opacity(0.18) : .clear)
                                .help("\(annotation.category.title) — \(PlaybackModel.timestamp(annotation.timing.start))")
                                .offset(x: min(width - 16, max(0, x(annotation.timing.start, width: width) - 8)))
                            }
                        }
                    }
                    .frame(width: width, height: 38)

                    Text("Playback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.25))
                            .frame(height: 8)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: x(displayedPosition, width: width), height: 8)
                    }
                    .frame(width: width, height: 38)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                playback.scrub(to: min(1, max(0, value.location.x / width)) * playback.duration)
                            }
                            .onEnded { value in
                                playback.endScrubbing(at: min(1, max(0, value.location.x / width)) * playback.duration)
                            }
                    )
                }
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(width: 3, height: 218)
                        .offset(x: min(width - 3, max(0, x(displayedPosition, width: width) - 1.5)), y: 19)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 250)
            .disabled(!playback.isReady || playback.duration <= 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Video timeline")
            .accessibilityValue("\(PlaybackModel.timestamp(displayedPosition)) of \(PlaybackModel.timestamp(playback.duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.seek(by: 1)
                case .decrement: playback.seek(by: -1)
                @unknown default: break
                }
            }
            HStack {
                Text(PlaybackModel.timestamp(displayedPosition))
                    .accessibilityLabel("Current time")
                Spacer()
                Text(PlaybackModel.timestamp(playback.duration))
                    .accessibilityLabel("Total duration")
            }
            .font(.caption)
            .monospacedDigit()
        }
    }
}

private struct PlayerView: NSViewRepresentable {
    let playback: PlaybackModel

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = playback.player
        context.coordinator.installKeyboardControls(for: view)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = playback.player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.removeKeyboardControls()
    }

    @MainActor
    final class Coordinator {
        let playback: PlaybackModel
        private var keyMonitor: Any?

        init(playback: PlaybackModel) { self.playback = playback }

        func installKeyboardControls(for view: AVPlayerView) {
            // Handle review keys even when a button or speed picker has focus, but never in the file picker.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, window.isKeyWindow,
                      event.window === window, window.attachedSheet == nil,
                      NSApp.modalWindow == nil,
                      !(window.firstResponder is NSTextView) else { return event }
                let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
                if modifiers == .shift, event.keyCode == 45 {
                    if !event.isARepeat { self.playback.markNextSegmentBoundary() }
                    return nil
                }
                if modifiers.isEmpty,
                   let characters = event.charactersIgnoringModifiers,
                   let number = Int(characters),
                   let category = AnnotationCategory(rawValue: number) {
                    if !event.isARepeat { self.playback.addAnnotation(category) }
                    return nil
                }
                switch (event.keyCode, modifiers) {
                case (4, [.command, .shift]):
                    if !event.isARepeat { self.playback.showsAnalysisOverlay.toggle() }
                case (49, []):
                    if !event.isARepeat { self.playback.togglePlayback() }
                case (123, []): self.playback.stepFrame(by: -1)
                case (124, []): self.playback.stepFrame(by: 1)
                case (123, .shift): self.playback.seek(by: -1)
                case (124, .shift): self.playback.seek(by: 1)
                default: return event
                }
                return nil
            }
        }

        func removeKeyboardControls() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }
}
