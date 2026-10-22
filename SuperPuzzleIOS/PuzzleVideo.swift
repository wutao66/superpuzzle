import AVFoundation
import CoreImage
import Combine
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 相册交付的文件只在导入回调中有效，复制到独立临时目录后再读取。
struct ImportedPuzzleVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(received.file.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: received.file, to: url)
                return Self(url: url)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }
}

/// 视频元数据与已按拍摄方向旋转的封面。
struct PuzzleVideoSource {
    let url: URL
    let asset: AVURLAsset
    let duration: Double
    let transform: CGAffineTransform
    let poster: CGImage

    static func prepare(url: URL) async throws -> Self {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.unreadable
        }
        let transform = try await track.load(.preferredTransform)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let poster = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, _, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? VideoError.unreadable) }
            }
        }
        return Self(url: url, asset: asset, duration: duration, transform: transform, poster: poster)
    }

    enum VideoError: LocalizedError {
        case unreadable
        var errorDescription: String? { "无法读取这个视频，请选择其他视频。" }
    }
}

/// 全棋盘只解码一份视频。共享帧交给单个绘图视图，不重新生成每块图片。
@MainActor
final class PuzzleVideoController: NSObject, ObservableObject {
    let frames = CurrentValueSubject<CGImage?, Never>(nil)
    var frame: CGImage? { frames.value }
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isMuted = true
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    private(set) var source: PuzzleVideoSource?
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pendingSeek: Double?
    private var isSeeking = false
    private var resumeAfterSeeking = false
    private var resumeAfterScrubbing = false
    private var renderingFrame = false
    private var sessionID = UUID()
    private var lastProgressUpdate: CFTimeInterval = 0

    var hasVideo: Bool { source != nil }

    func configure(_ source: PuzzleVideoSource) {
        reset()
        self.source = source
        frames.send(source.poster)
        duration = source.duration
        let item = AVPlayerItem(asset: source.asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        self.output = output
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        self.player = player
        let session = sessionID
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                self.isReady = item.status == .readyToPlay
                if item.status == .failed {
                    self.errorMessage = "视频播放失败，请重新选择视频。"
                    self.pause()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.sessionID == session, self.isPlaying, !self.isSeeking else { return }
                self.resumeAfterSeeking = self.isPlaying
                self.seek(to: 0)
            }
        }
        // 弱引用代理避免 display link 与控制器互相持有。
        let link = CADisplayLink(target: VideoDisplayLinkTarget(controller: self), selector: #selector(VideoDisplayLinkTarget.tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func play() {
        guard player != nil, errorMessage == nil else { return }
        isPlaying = true
        player?.play()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        resumeAfterSeeking = false
        resumeAfterScrubbing = false
    }

    func togglePlayback() { isPlaying ? pause() : play() }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func beginScrubbing() {
        let resume = isPlaying
        pause()
        resumeAfterScrubbing = resume
    }

    func endScrubbing(at seconds: Double) {
        resumeAfterSeeking = resumeAfterScrubbing
        resumeAfterScrubbing = false
        seek(to: seconds)
    }

    /// 合并快速拖拽请求，始终完成最后一次定位，避免异步回调乱序。
    func seek(to seconds: Double) {
        guard seconds.isFinite, player != nil else { return }
        pendingSeek = min(max(0, seconds), duration)
        if !isSeeking { performPendingSeek() }
    }

    private func performPendingSeek() {
        guard let seconds = pendingSeek, let player else { return }
        pendingSeek = nil
        isSeeking = true
        let session = sessionID
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                let time = player.currentTime().seconds
                if time.isFinite { self.currentTime = min(max(0, time), self.duration) }
                self.isSeeking = false
                self.refreshFrame()
                if self.pendingSeek != nil {
                    self.performPendingSeek()
                } else if self.resumeAfterSeeking {
                    self.resumeAfterSeeking = false
                    self.play()
                }
            }
        }
    }

    fileprivate func refreshFrame() {
        guard let player, let output, let source else { return }
        let time = player.currentTime()
        let now = CACurrentMediaTime()
        if now - lastProgressUpdate > 0.1, time.seconds.isFinite {
            currentTime = min(max(0, time.seconds), duration)
            lastProgressUpdate = now
        }
        guard !renderingFrame, output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        renderingFrame = true
        let session = sessionID
        let context = context
        let transform = source.transform
        let inputImage = CIImage(cvPixelBuffer: buffer)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var image = inputImage.transformed(by: transform)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            let scale = min(1, 1280 / max(image.extent.width, image.extent.height))
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let frame = context.createCGImage(image, from: image.extent)
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                self.renderingFrame = false
                if let frame { self.frames.send(frame) }
            }
        }
    }

    /// 离开素材时释放播放器、监听和导入文件。
    func reset() {
        sessionID = UUID()
        pause()
        displayLink?.invalidate()
        displayLink = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        output = nil
        if let source { Self.removeImportedFile(at: source.url) }
        source = nil
        frames.send(nil)
        duration = 0
        currentTime = 0
        isMuted = true
        isReady = false
        errorMessage = nil
        pendingSeek = nil
        isSeeking = false
        renderingFrame = false
    }

    static func removeImportedFile(at url: URL) {
        // 只删除导入器创建的 UUID 子目录，避免触碰其他来源的文件。
        let directory = url.deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        guard directory.deletingLastPathComponent().standardizedFileURL == temporary,
              UUID(uuidString: directory.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    deinit {
        displayLink?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player?.pause()
    }
}

private final class VideoDisplayLinkTarget: NSObject {
    weak var controller: PuzzleVideoController?
    init(controller: PuzzleVideoController) { self.controller = controller }
    @MainActor @objc func tick() { controller?.refreshFrame() }
}

/// 视频专用控制条；拖动时临时暂停，结束后恢复拖动前的播放状态。
struct PuzzleVideoControls: View {
    @ObservedObject var video: PuzzleVideoController
    let language: AppLanguage
    @State private var scrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: video.togglePlayback) {
                    Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(video.isPlaying ? language.text("暂停视频", "Pause Video") : language.text("播放视频", "Play Video"))
                .accessibilityIdentifier("videoPlayback")
                .disabled(scrubbing || !video.isReady)
                Text("\(timeText(scrubbing ? scrubTime : video.currentTime)) / \(timeText(video.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.puzzleIvory)
                Spacer(minLength: 0)
                Button(action: video.toggleMute) {
                    Image(systemName: video.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(video.isMuted ? language.text("取消静音", "Unmute") : language.text("静音", "Mute"))
                .accessibilityIdentifier("videoMute")
            }
            Slider(value: Binding(get: {
                scrubbing ? scrubTime : video.currentTime
            }, set: { value in
                scrubTime = value
                video.seek(to: value)
            }), in: 0...max(video.duration, 0.001), onEditingChanged: { editing in
                if editing {
                    scrubTime = video.currentTime
                    scrubbing = true
                    video.beginScrubbing()
                } else {
                    scrubbing = false
                    video.endScrubbing(at: scrubTime)
                }
            })
            .accessibilityLabel(language.text("视频进度", "Video Progress"))
            .accessibilityIdentifier("videoProgress")
            .disabled(!video.isReady)
            if video.errorMessage != nil {
                Text(language.text("视频播放失败，请重新选择视频。", "Video playback failed. Please choose another video."))
                    .font(.caption).foregroundStyle(Color.puzzleIvory)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.puzzleBrass)
        .tint(Color.puzzleBrass)
        .padding(12)
        .background(Color.puzzleCharcoal.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func timeText(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
