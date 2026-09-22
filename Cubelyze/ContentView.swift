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
            HStack(spacing: 12) {
                PlayerView(playback: playback)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 8) {
                    AnnotationList(playback: playback)
                        .frame(maxHeight: .infinity)
                    Divider()
                    SegmentList(playback: playback)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 270)
            }
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
                Text("Mark:")
                ForEach(AnnotationCategory.allCases, id: \.self) { category in
                    Button("\(category.rawValue) \(category.title)") {
                        playback.addAnnotation(category)
                    }
                    .help("Mark \(category.title) at the current time (\(category.rawValue))")
                }
                Spacer(minLength: 0)
            }
            .disabled(!playback.isReady)
            HStack {
                Text("Segment:")
                ForEach(SolveSegmentType.allCases, id: \.self) { type in
                    Button("\(type.rawValue) \(type.title)") {
                        playback.markSegmentBoundary(type)
                    }
                    .help("Mark \(type.title) boundary (Shift+\(type.rawValue))")
                }
                if playback.pendingSegment != nil {
                    Button("Cancel") { playback.cancelPendingSegment() }
                        .help("Cancel the uncompleted segment")
                }
                Spacer(minLength: 0)
            }
            .disabled(!playback.isReady)
            if let pending = playback.pendingSegment {
                Text("\(pending.type.title) start: \(PlaybackModel.timestamp(pending.start)) — mark its end with Shift+\(pending.type.rawValue)")
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
        .frame(minWidth: 920, minHeight: 480)
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
                Text("Press Shift+1–7 to mark a start, then the same key to mark its end.")
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
                            .help("Delete segment")
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
    @State private var type: SolveSegmentType
    @State private var caseLabel: String
    @State private var error: String?

    init(playback: PlaybackModel, segment: SolveSegment) {
        self.playback = playback
        self.segment = segment
        _startText = State(initialValue: String(format: "%.3f", segment.start))
        _endText = State(initialValue: String(format: "%.3f", segment.end))
        _type = State(initialValue: segment.type)
        _caseLabel = State(initialValue: segment.caseLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(segment.type.title)")
                .font(.headline)
            Picker("Type", selection: $type) {
                ForEach(SolveSegmentType.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
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
                          playback.updateSegment(segment, type: type, start: start, end: end, caseLabel: caseLabel) else {
                        error = "Enter times within the video, with end later than start."
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
                Text("Press 1–6 to mark the current moment.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(playback.annotations) { annotation in
                    HStack {
                        Button {
                            playback.seek(to: annotation.timestamp)
                        } label: {
                            HStack {
                                Text(PlaybackModel.timestamp(annotation.timestamp))
                                    .monospacedDigit()
                                Text(annotation.category.title)
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
                        .accessibilityLabel("Delete \(annotation.category.title) at \(PlaybackModel.timestamp(annotation.timestamp))")
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

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let fraction = playback.duration > 0 ? min(1, max(0, displayedPosition / playback.duration)) : 0
                VStack(spacing: 2) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.25))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: width * fraction, height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary)
                            .frame(width: 3, height: 22)
                            .offset(x: min(width - 3, max(0, width * fraction - 1.5)))
                    }
                    .frame(width: width, height: 30)
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
                    .overlay(alignment: .leading) {
                        ZStack(alignment: .leading) {
                            ForEach(playback.annotations) { annotation in
                                let markerFraction = playback.duration > 0 ? min(1, max(0, annotation.timestamp / playback.duration)) : 0
                                Button {
                                    playback.seek(to: annotation.timestamp)
                                } label: {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 12))
                                        .frame(width: 14, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                                .help("\(annotation.category.title) — \(PlaybackModel.timestamp(annotation.timestamp))")
                                .accessibilityLabel("\(annotation.category.title) at \(PlaybackModel.timestamp(annotation.timestamp))")
                                .offset(x: min(width - 14, max(0, width * markerFraction - 7)))
                            }
                        }
                    }
                    ZStack(alignment: .leading) {
                        ForEach(playback.segments) { segment in
                            let start = playback.duration > 0 ? segment.start / playback.duration : 0
                            let length = playback.duration > 0 ? segment.duration / playback.duration : 0
                            Button {
                                playback.seek(to: segment.start)
                            } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(0.65))
                                    .frame(width: max(2, width * length), height: 14)
                            }
                            .buttonStyle(.plain)
                            .help("\(segment.type.title) \(PlaybackModel.timestamp(segment.start))–\(PlaybackModel.timestamp(segment.end))\(segment.caseLabel.isEmpty ? "" : " — \(segment.caseLabel)")")
                            .accessibilityLabel("\(segment.type.title) segment, \(PlaybackModel.timestamp(segment.start)) to \(PlaybackModel.timestamp(segment.end))")
                            .offset(x: min(width - 2, max(0, width * start)))
                        }
                    }
                    .frame(width: width, height: 16)
                }
            }
            .frame(height: 48)
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
                if modifiers == .shift, let index = [18, 19, 20, 21, 23, 22, 26].firstIndex(of: Int(event.keyCode)),
                   let type = SolveSegmentType(rawValue: index + 1) {
                    if !event.isARepeat { self.playback.markSegmentBoundary(type) }
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
