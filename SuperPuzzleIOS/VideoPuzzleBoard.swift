import Combine
import SwiftUI

/// 直接订阅共享视频帧，播放时不会触发整个 SwiftUI 棋盘重新布局。
struct VideoPuzzleBoard: UIViewRepresentable {
    let video: PuzzleVideoController
    let pieces: [PuzzlePiece]
    let rows: Int
    let columns: Int
    var draggedIndex: Int?
    var translation: CGSize = .zero
    var selectedIndex: Int?
    var hintedIndices: [Int] = []

    func makeUIView(context: Context) -> VideoBoardCanvas {
        let view = VideoBoardCanvas()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.connect(video)
        return view
    }

    func updateUIView(_ view: VideoBoardCanvas, context: Context) {
        view.configure(pieces: pieces, rows: rows, columns: columns, draggedIndex: draggedIndex,
                       translation: translation, selectedIndex: selectedIndex, hintedIndices: hintedIndices)
    }
}

/// 布局只在拼图或尺寸变化时计算；逐帧合成在后台完成，主线程只提交一张图。
final class VideoBoardCanvas: UIView {
    private struct Slot: Equatable {
        let id: Int
        let edges: PuzzleEdges
    }

    private struct Configuration: Equatable {
        let slots: [Slot]
        let rows: Int
        let columns: Int
        let draggedIndex: Int?
        let translation: CGSize
        let selectedIndex: Int?
        let hintedIndices: [Int]
    }

    private struct DrawCommand {
        let index: Int
        let origin: CGPoint
        let clip: CGPath
        let imageRect: CGRect
    }

    // CGImage 和 CGPath 都是不可变快照，后台不访问 UIView 或可变布局。
    private struct RenderRequest: @unchecked Sendable {
        let frame: CGImage
        let size: CGSize
        let scale: CGFloat
        let commands: [DrawCommand]
        let draggedIndex: Int?
        let translation: CGSize

        func render() -> CGImage? {
            autoreleasepool {
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                format.opaque = false
                return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                    let context = renderer.cgContext
                    context.interpolationQuality = .medium
                    let image = UIImage(cgImage: frame)
                    for command in commands {
                        context.saveGState()
                        let offset = command.index == draggedIndex ? translation : .zero
                        context.translateBy(x: command.origin.x + offset.width, y: command.origin.y + offset.height)
                        context.addPath(command.clip)
                        context.clip()
                        image.draw(in: command.imageRect)
                        context.restoreGState()
                    }
                }.cgImage
            }
        }
    }

    private let renderQueue = DispatchQueue(label: "superpuzzle.video.board", qos: .userInitiated)
    private var subscription: AnyCancellable?
    private var videoFrame: CGImage?
    private var configuration: Configuration?
    private var commands: [DrawCommand] = []
    private var layoutSize: CGSize = .zero
    private var rendering = false
    private var needsRender = false
    private var generation = UUID()
    private(set) var renderedFrame: CGImage?

    func connect(_ video: PuzzleVideoController) {
        subscription = video.frames.sink { [weak self] frame in
            guard let self else { return }
            self.videoFrame = frame
            if frame == nil {
                self.generation = UUID()
                self.renderedFrame = nil
                self.layer.contents = nil
                self.needsRender = false
            } else {
                self.requestRender()
            }
        }
    }

    func configure(pieces: [PuzzlePiece], rows: Int, columns: Int, draggedIndex: Int?, translation: CGSize,
                   selectedIndex: Int?, hintedIndices: [Int]) {
        let next = Configuration(slots: pieces.map { Slot(id: $0.id, edges: $0.edges) }, rows: rows, columns: columns,
                                 draggedIndex: draggedIndex, translation: translation,
                                 selectedIndex: selectedIndex, hintedIndices: hintedIndices)
        guard configuration != next else { return }
        let previous = configuration
        configuration = next
        // 手指位移不会改变轮廓与排列，不在每次拖动时重建整盘绘制指令。
        if previous?.slots != next.slots || previous?.rows != next.rows || previous?.columns != next.columns
            || previous?.selectedIndex != next.selectedIndex || previous?.hintedIndices != next.hintedIndices {
            rebuildCommands()
        }
        requestRender()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard layoutSize != bounds.size else { return }
        layoutSize = bounds.size
        rebuildCommands()
        requestRender()
    }

    private func rebuildCommands() {
        commands = []
        guard let configuration, configuration.rows > 0, configuration.columns > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let columns = configuration.columns
        let cell = CGSize(width: bounds.width / CGFloat(columns), height: bounds.height / CGFloat(configuration.rows))
        var paths: [PuzzleEdges: CGPath] = [:]
        let foreground = configuration.slots.indices.filter {
            $0 == configuration.selectedIndex || configuration.hintedIndices.contains($0)
        }
        let order = configuration.slots.indices.filter { !foreground.contains($0) }
            + foreground.filter { $0 != configuration.selectedIndex }
            + foreground.filter { $0 == configuration.selectedIndex }
        commands = order.map { index in
            let piece = configuration.slots[index]
            let path: CGPath
            if let cached = paths[piece.edges] {
                path = cached
            } else {
                path = PuzzlePieceShape(edges: piece.edges).path(in: CGRect(
                    x: -cell.width * 0.18, y: -cell.height * 0.18,
                    width: cell.width * 1.36, height: cell.height * 1.36)).cgPath
                paths[piece.edges] = path
            }
            return DrawCommand(
                index: index,
                origin: CGPoint(x: CGFloat(index % columns) * cell.width,
                                y: CGFloat(index / columns) * cell.height),
                clip: path,
                imageRect: CGRect(x: -CGFloat(piece.id % columns) * cell.width,
                                  y: -CGFloat(piece.id / columns) * cell.height,
                                  width: bounds.width, height: bounds.height))
        }
    }

    private func requestRender() {
        needsRender = true
        renderNextFrameIfNeeded()
    }

    /// 最多一帧在计算，其余更新合并成最新一帧，不积压视频帧或拖动布局。
    private func renderNextFrameIfNeeded() {
        guard needsRender, !rendering, let videoFrame, !commands.isEmpty,
              bounds.width > 0, bounds.height > 0 else { return }
        needsRender = false
        rendering = true
        let session = generation
        let request = RenderRequest(frame: videoFrame, size: bounds.size,
                                    scale: min(contentScaleFactor, 1280 / max(bounds.width, bounds.height)), commands: commands,
                                    draggedIndex: configuration?.draggedIndex, translation: configuration?.translation ?? .zero)
        renderQueue.async { [weak self] in
            let image = request.render()
            Task { @MainActor in
                guard let self else { return }
                self.rendering = false
                if self.generation == session, let image {
                    self.renderedFrame = image
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.layer.contents = image
                    CATransaction.commit()
                }
                self.renderNextFrameIfNeeded()
            }
        }
    }
}

/// 设置页中的整幅视频预览，仍与拼图共用同一播放器。
struct PuzzleVideoPreview: UIViewRepresentable {
    let video: PuzzleVideoController

    func makeUIView(context: Context) -> VideoPreviewCanvas {
        let view = VideoPreviewCanvas()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.connect(video)
        return view
    }

    func updateUIView(_ view: VideoPreviewCanvas, context: Context) {}
}

final class VideoPreviewCanvas: UIView {
    private var subscription: AnyCancellable?
    private var videoFrame: CGImage?

    func connect(_ video: PuzzleVideoController) {
        subscription = video.frames.sink { [weak self] frame in
            self?.videoFrame = frame
            self?.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let frame = videoFrame else { return }
        let size = CGSize(width: frame.width, height: frame.height)
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        UIImage(cgImage: frame).draw(in: CGRect(x: (bounds.width - fitted.width) / 2,
                                              y: (bounds.height - fitted.height) / 2,
                                              width: fitted.width, height: fitted.height))
    }

    override func layoutSubviews() { super.layoutSubviews(); setNeedsDisplay() }
}
