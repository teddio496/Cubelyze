import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackModel()
    private let refreshTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

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
            PlayerView(player: playback.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button(playback.isPlaying ? "Pause" : "Play", action: playback.togglePlayback)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!playback.isReady)
                Text("\(PlaybackModel.timestamp(playback.position)) / \(PlaybackModel.timestamp(playback.duration))")
                    .monospacedDigit()
                    .accessibilityLabel("Playback position")
                Spacer()
            }
            if let error = playback.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
        .onReceive(refreshTimer) { _ in playback.refresh() }
        .onDisappear { playback.player.pause() }
    }
}

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
