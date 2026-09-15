import SwiftUI
import UIKit

/// 拼图难度及其对应的拼图数量。
enum PuzzleDifficulty: String, CaseIterable, Identifiable {
    case easy = "简单"
    case normal = "普通"
    case hard = "困难"
    case nightmare = "噩梦"
    case hell = "地狱"

    /// 用于 SwiftUI 列表识别的稳定标识。
    var id: String { rawValue }

    /// 当前难度的拼图总数。
    var pieceCount: Int {
        switch self {
        case .easy: return 9
        case .normal: return 100
        case .hard: return 300
        case .nightmare: return 1000
        case .hell: return 2000
        }
    }
}

/// 单块拼图，包含异形图片和四条拼接边。
struct PuzzlePiece: Identifiable {
    /// 拼图原始位置。
    let id: Int
    /// 当前显示的图片内容。
    let image: UIImage
    /// 拼图四条边的榫槽形态。
    let edges: PuzzleEdges
}

/// 拼图状态、切片和交换逻辑。
@MainActor
final class PuzzleViewModel: ObservableObject {
    /// 用户当前选择的难度。
    @Published var difficulty: PuzzleDifficulty = .easy
    /// 当前棋盘中的拼图排列。
    @Published private(set) var pieces: [PuzzlePiece] = []
    /// 已选择、等待交换的棋盘位置。
    @Published var selectedIndex: Int?
    /// 当前计时秒数。
    @Published private(set) var elapsedSeconds = 0
    /// 是否已经开始游戏。
    @Published private(set) var isPlaying = false
    /// 是否完成当前拼图。
    @Published private(set) var isComplete = false
    /// 原图宽高比。
    private(set) var imageAspect: CGFloat = 16 / 9
    /// 计时器任务。
    private var timer: Timer?

    /// 当前难度对应的最优矩形行列数。
    var grid: (rows: Int, columns: Int) {
        let count = difficulty.pieceCount
        var result = (rows: 1, columns: count, score: CGFloat.infinity)
        for rows in 1...Int(Double(count).squareRoot()) where count % rows == 0 {
            let columns = count / rows
            let score = abs(log(CGFloat(columns) / CGFloat(rows) / imageAspect))
            if score < result.score { result = (rows, columns, score) }
        }
        return (result.rows, result.columns)
    }

    /// 根据相册图片创建矩形拼图块。
    /// - Parameter image: 用户选择的原图。
    func start(with image: UIImage) {
        stopTimer()
        imageAspect = image.size.width / max(image.size.height, 1)
        let layout = grid
        pieces = Self.slice(image: image, rows: layout.rows, columns: layout.columns)
        shuffle()
        isPlaying = true
        isComplete = false
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.elapsedSeconds += 1 }
    }

    /// 重新打乱当前棋盘。
    func shuffle() {
        guard !pieces.isEmpty else { return }
        repeat { pieces.shuffle() } while pieces.enumerated().allSatisfy { $0.offset == $0.element.id }
        selectedIndex = nil
        isComplete = false
    }

    /// 处理用户点击并在第二次点击时交换两块拼图。
    /// - Parameter index: 被点击的棋盘位置。
    func tap(index: Int) {
        guard !isComplete else { return }
        if let first = selectedIndex {
            guard first != index else { selectedIndex = nil; return }
            pieces.swapAt(first, index)
            selectedIndex = nil
            isComplete = pieces.enumerated().allSatisfy { $0.offset == $0.element.id }
            if isComplete { stopTimer() }
        } else { selectedIndex = index }
    }

    /// 停止计时器并释放资源。
    func stopTimer() { timer?.invalidate(); timer = nil }

    /// 将原图按照行列裁成带互补榫槽的异形拼图图片。
    /// - Parameters:
    ///   - image: 原始图片。
    ///   - rows: 行数。
    ///   - columns: 列数。
    /// - Returns: 按从左到右、从上到下排列的拼图块。
    private static func slice(image: UIImage, rows: Int, columns: Int) -> [PuzzlePiece] {
        let source = normalizedImage(image)
        let cellWidth = source.size.width / CGFloat(columns)
        let cellHeight = source.size.height / CGFloat(rows)
        let marginX = cellWidth * 0.18
        let marginY = cellHeight * 0.18
        return (0..<(rows * columns)).map { index in
            let row = index / columns
            let column = index % columns
            let edges = edges(row: row, column: column, rows: rows, columns: columns)
            let renderSize = CGSize(width: cellWidth + marginX * 2, height: cellHeight + marginY * 2)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let pieceImage = UIGraphicsImageRenderer(size: renderSize, format: format).image { context in
                let shape = PuzzlePieceShape(edges: edges).path(in: CGRect(origin: .zero, size: renderSize))
                context.cgContext.addPath(shape.cgPath)
                context.cgContext.clip()
                source.draw(at: CGPoint(x: marginX - CGFloat(column) * cellWidth, y: marginY - CGFloat(row) * cellHeight))
            }
            return PuzzlePiece(id: index, image: pieceImage, edges: edges)
        }
    }

    /// 生成指定位置的四条边，并保证相邻拼图的榫槽严格互补。
    /// - Parameters:
    ///   - row: 拼图所在行。
    ///   - column: 拼图所在列。
    ///   - rows: 总行数。
    ///   - columns: 总列数。
    /// - Returns: 当前拼图四条边的形态。
    private static func edges(row: Int, column: Int, rows: Int, columns: Int) -> PuzzleEdges {
        let top = row == 0 ? PuzzleEdge.flat : boundaryEdge(row: row - 1, column: column).opposite
        let left = column == 0 ? PuzzleEdge.flat : boundaryEdge(row: row, column: column - 1).opposite
        let right = column == columns - 1 ? PuzzleEdge.flat : boundaryEdge(row: row, column: column)
        let bottom = row == rows - 1 ? PuzzleEdge.flat : boundaryEdge(row: row, column: column)
        return PuzzleEdges(top: top, right: right, bottom: bottom, left: left)
    }

    /// 根据网格坐标稳定生成凸榫或凹槽。
    /// - Parameters:
    ///   - row: 边所在行。
    ///   - column: 边所在列。
    /// - Returns: 当前边的确定形态。
    private static func boundaryEdge(row: Int, column: Int) -> PuzzleEdge {
        (row * 31 + column * 17).isMultiple(of: 2) ? .outward : .inward
    }

    /// 修正图片方向并限制处理尺寸，避免高难度切片占用过多内存。
    /// - Parameter image: 相册读取的原图。
    /// - Returns: 方向正确且最长边不超过 2048 像素的图片。
    private static func normalizedImage(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2048
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
