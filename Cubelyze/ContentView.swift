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
                AnnotationList(playback: playback)
                    .frame(width: 240)
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
            if let error = playback.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 400)
        .onReceive(refreshTimer) { _ in playback.refresh() }
        .onDisappear { playback.player.pause() }
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
            }
            .frame(height: 30)
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
