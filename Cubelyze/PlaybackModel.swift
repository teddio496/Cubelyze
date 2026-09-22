import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var filename: String?
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published var errorMessage: String?

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open Video"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
    }

    func open(_ url: URL) {
        player.pause()
        filename = url.lastPathComponent
        position = 0
        duration = 0
        isReady = false
        isPlaying = false
        errorMessage = nil
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    func togglePlayback() {
        guard isReady else { return }
        if player.rate != 0 {
            player.pause()
        } else {
            // Some files end on a frame just before their reported duration.
            if duration > 0, position >= duration - 0.1 {
                player.seek(to: .zero)
            }
            player.play()
        }
        refresh()
    }

    func refresh() {
        guard let item = player.currentItem else { return }
        isReady = item.status == .readyToPlay
        isPlaying = player.rate != 0
        let current = player.currentTime().seconds
        let total = item.duration.seconds
        position = current.isFinite ? max(0, current) : 0
        duration = total.isFinite ? max(0, total) : 0
        if item.status == .failed, errorMessage == nil {
            errorMessage = item.error?.localizedDescription ?? "This video could not be played."
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
        }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
