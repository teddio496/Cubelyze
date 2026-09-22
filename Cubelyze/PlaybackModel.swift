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
    @Published private(set) var speed: Float = 1
    @Published private(set) var scrubPosition: Double?
    @Published var errorMessage: String?
    private var seekTarget: CMTime?
    private var isSeeking = false
    private var pendingSteps = 0
    private var isScrubbing = false
    private var playAfterSeek = false
    private var reachedEnd = false
    private var endObserver: NSObjectProtocol?

    init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                self.reachedEnd = true
                self.refresh()
            }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

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
        seekTarget = nil
        isSeeking = false
        pendingSteps = 0
        isScrubbing = false
        playAfterSeek = false
        scrubPosition = nil
        reachedEnd = false
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    func togglePlayback() {
        guard isReady else { return }
        if isSeeking || isScrubbing {
            playAfterSeek.toggle()
            refresh()
            return
        }
        if player.rate != 0 {
            player.pause()
        } else {
            if reachedEnd {
                reachedEnd = false
                playAfterSeek = true
                seekTarget = .zero
                seekToTarget()
                refresh()
                return
            }
            player.play()
        }
        refresh()
    }

    func setSpeed(_ value: Float) {
        speed = value
        player.defaultRate = value
        if player.rate != 0 { player.rate = value }
        refresh()
    }

    func stepFrame(by count: Int) {
        guard isReady, let item = player.currentItem else { return }
        player.pause()
        playAfterSeek = false
        reachedEnd = false
        guard count > 0 ? item.canStepForward : item.canStepBackward else {
            errorMessage = "This video does not support stepping in that direction."
            refresh()
            return
        }
        if isSeeking {
            pendingSteps += count
        } else {
            item.step(byCount: count)
        }
        refresh()
    }

    func seek(by seconds: Double) {
        guard isReady else { return }
        let base = seekTarget?.seconds ?? player.currentTime().seconds
        seek(to: base + seconds)
    }

    func scrub(to seconds: Double) {
        guard isReady, duration > 0 else { return }
        if !isScrubbing {
            playAfterSeek = isPlaying
            isScrubbing = true
        }
        scrubPosition = min(duration, max(0, seconds))
        seek(to: seconds)
    }

    func endScrubbing(at seconds: Double) {
        scrub(to: seconds)
        isScrubbing = false
    }

    private func seek(to seconds: Double) {
        guard isReady else { return }
        reachedEnd = false
        if !isSeeking && !isScrubbing { playAfterSeek = player.rate != 0 }
        player.pause()
        seekTarget = CMTime(seconds: min(duration, max(0, seconds)), preferredTimescale: 60_000)
        if !isSeeking { seekToTarget() }
        refresh()
    }

    private func seekToTarget() {
        guard let target = seekTarget, let item = player.currentItem else { return }
        isSeeking = true
        // Coalesce drag/key-repeat requests without continually cancelling frame decoding.
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if finished, self.seekTarget != target {
                    self.seekToTarget()
                    return
                }
                self.isSeeking = false
                self.seekTarget = nil
                if self.pendingSteps != 0 {
                    item.step(byCount: self.pendingSteps)
                    self.pendingSteps = 0
                }
                if !self.isScrubbing {
                    self.scrubPosition = nil
                    if self.playAfterSeek { self.player.play() }
                }
                self.refresh()
            }
        }
    }

    func refresh() {
        guard let item = player.currentItem else { return }
        isReady = item.status == .readyToPlay
        isPlaying = isSeeking || isScrubbing ? playAfterSeek : player.rate != 0
        let current = player.currentTime().seconds
        let total = item.duration.seconds
        position = current.isFinite ? max(0, current) : 0
        duration = total.isFinite ? max(0, total) : 0
        if item.status == .failed, errorMessage == nil {
            errorMessage = item.error?.localizedDescription ?? "This video could not be played."
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00.000" }
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let value = milliseconds / 1000
        if value >= 3600 {
            return String(format: "%d:%02d:%02d.%03d", value / 3600, value / 60 % 60, value % 60, milliseconds % 1000)
        }
        return String(format: "%d:%02d.%03d", value / 60, value % 60, milliseconds % 1000)
    }
}
