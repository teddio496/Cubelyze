import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackModel()
    private let refreshTimer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Open Video…", action: playback.chooseVideo)
                    .keyboardShortcut("o")
                Text(playback.filename ?? "Choose a local video to begin")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            GeometryReader { row in
                HStack(spacing: 12) {
                    PlayerView(playback: playback)
                        .frame(width: min(row.size.width * 0.72, row.size.height * playback.videoAspectRatio),
                               height: row.size.height)
                    VStack(spacing: 8) {
                        AnnotationList(playback: playback)
                            .frame(maxHeight: .infinity)
                        Divider()
                        SegmentList(playback: playback)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            ReviewTimeline(playback: playback)
            HStack {
                Button(playback.isPlaying ? "Pause" : "Play", action: playback.togglePlayback)
                    .help("Play/Pause (Space)")
                    .disabled(!playback.isReady)
                Button("−1s") { playback.seek(by: -1) }
                    .help("Back one second (Shift+Left Arrow)")
                    .disabled(!playback.isReady)
                Button { playback.stepFrame(by: -1) } label: {
                    Image(systemName: "backward.frame")
                }
                .accessibilityLabel("Previous frame")
                .help("Previous frame (Left Arrow)")
                .disabled(!playback.isReady)
                Button { playback.stepFrame(by: 1) } label: {
                    Image(systemName: "forward.frame")
                }
                .accessibilityLabel("Next frame")
                .help("Next frame (Right Arrow)")
                .disabled(!playback.isReady)
                Button("+1s") { playback.seek(by: 1) }
                    .help("Forward one second (Shift+Right Arrow)")
                    .disabled(!playback.isReady)
                Spacer()
                Picker("Speed", selection: Binding(get: { playback.speed }, set: playback.setSpeed)) {
                    Text("0.25×").tag(Float(0.25))
                    Text("0.5×").tag(Float(0.5))
                    Text("1×").tag(Float(1))
                    Text("2×").tag(Float(2))
                }
                .fixedSize()
            }
            HStack {
                Text("Events:")
                ForEach(AnnotationCategory.allCases, id: \.self) { category in
                    Button("\(category.rawValue) \(category.title)") {
                        playback.addAnnotation(category)
                    }
                    .help(category.isInterval
                          ? "Start/end \(category.title) (\(category.rawValue))"
                          : "Mark \(category.title) at the current time (\(category.rawValue))")
                }
                Spacer(minLength: 0)
            }
            .disabled(!playback.isReady)
            HStack {
                Text("Solve:")
                Button("Next Segment") {
                    playback.markNextSegmentBoundary()
                }
                .help("Start Cross or complete the current segment (Shift+N)")
                if playback.pendingSegment != nil {
                    Button("Cancel") { playback.cancelPendingSegment() }
                        .help("Cancel the uncompleted segment")
                }
                Spacer(minLength: 0)
            }
            .disabled(!playback.isReady)
            if let pending = playback.pendingSegment {
                Text("\(pending.type.title) from \(PlaybackModel.timestamp(pending.start)) — Next Segment (Shift+N) marks completion")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let pending = playback.pendingAnnotation {
                HStack {
                    Text("\(pending.category.title) from \(PlaybackModel.timestamp(pending.start)) — press \(pending.category.rawValue) again to end")
                    Button("Cancel") { playback.cancelPendingAnnotation() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = playback.annotationMessage {
                Text(message).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = playback.segmentMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = playback.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 920, minHeight: 760)
        .onReceive(refreshTimer) { _ in playback.refresh() }
        .onDisappear { playback.player.pause() }
    }
}

private struct SegmentList: View {
    @ObservedObject var playback: PlaybackModel
    @State private var editingSegment: SolveSegment?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Segments (\(playback.segments.count))")
            if playback.segments.isEmpty {
                Text("Press Next Segment (Shift+N) to start Cross, then again at each completion.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(playback.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button {
                                playback.seek(to: segment.start)
                            } label: {
                                Text(segment.type.title)
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button("Edit") { editingSegment = segment }
                                .buttonStyle(.borderless)
                            Button {
                                playback.deleteSegment(segment)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this and later segments")
                        }
                        Button {
                            playback.seek(to: segment.start)
                        } label: {
                            Text("\(PlaybackModel.timestamp(segment.start))–\(PlaybackModel.timestamp(segment.end)) (\(PlaybackModel.timestamp(segment.duration)))")
                                .font(.caption)
                                .monospacedDigit()
                        }
                        .buttonStyle(.plain)
                        if !segment.caseLabel.isEmpty {
                            Text(segment.caseLabel)
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditor(playback: playback, segment: segment)
        }
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

private struct AnnotationList: View {
    @ObservedObject var playback: PlaybackModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Annotations (\(playback.annotations.count))")
            if playback.annotations.isEmpty {
                Text("Press 1 twice for a pause; 7 twice for recognition delay. Other keys mark points.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(playback.annotations) { annotation in
                    HStack {
                        Button {
                            playback.seek(to: annotation.timing.start)
                        } label: {
                            HStack {
                                Text(PlaybackModel.timestamp(annotation.timing.start))
                                    .monospacedDigit()
                                if let end = annotation.timing.end {
                                    Text("–\(PlaybackModel.timestamp(end))")
                                        .monospacedDigit()
                                }
                                Text(annotation.category.title)
                                if let duration = annotation.timing.duration {
                                    Text("\(PlaybackModel.timestamp(duration))")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            playback.deleteAnnotation(annotation)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete annotation")
                        .accessibilityLabel("Delete \(annotation.category.title) at \(PlaybackModel.timestamp(annotation.timing.start))")
                    }
                }
                .listStyle(.plain)
            }
        }
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
                                playback.seek(to: segment.start)
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
                                .frame(width: blockWidth, height: 56, alignment: .leading)
                                .background(Color.blue.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
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
                                .frame(width: max(2, x(displayedPosition, width: width) - x(pending.start, width: width)), height: 56, alignment: .leading)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .offset(x: x(pending.start, width: width))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: width, height: 56)

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
                                    playback.seek(to: annotation.timing.start)
                                } label: {
                                    Text(spanWidth >= 75 ? annotation.category.title : "")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 3)
                                        .frame(width: spanWidth, height: 26, alignment: .leading)
                                        .background(Color.orange.opacity(0.55))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .help("\(annotation.category.title): \(PlaybackModel.timestamp(annotation.timing.start))–\(PlaybackModel.timestamp(end))")
                                .offset(x: x(annotation.timing.start, width: width))
                            }
                        }
                    }
                    .frame(width: width, height: 26)

                    Text("Point events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(playback.annotations) { annotation in
                            if annotation.timing.end == nil {
                                Button {
                                    playback.seek(to: annotation.timing.start)
                                } label: {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 12))
                                        .frame(width: 16, height: 26)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                                .help("\(annotation.category.title) — \(PlaybackModel.timestamp(annotation.timing.start))")
                                .offset(x: min(width - 16, max(0, x(annotation.timing.start, width: width) - 8)))
                            }
                        }
                    }
                    .frame(width: width, height: 26)

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
                    .frame(width: width, height: 32)
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
                        .frame(width: 3, height: 205)
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
                      NSApp.modalWindow == nil else { return event }
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
