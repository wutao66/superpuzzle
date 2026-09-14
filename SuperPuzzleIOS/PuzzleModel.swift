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

/// 单块拼图，image 是已经按矩形网格裁切后的图片。
struct PuzzlePiece: Identifiable {
    /// 拼图原始位置。
    let id: Int
    /// 当前显示的图片内容。
    let image: UIImage
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
    private var imageAspect: CGFloat = 16 / 9
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

    /// 将原图按照行列裁成矩形图片，保持图片完整比例。
    /// - Parameters:
    ///   - image: 原始图片。
    ///   - rows: 行数。
    ///   - columns: 列数。
    /// - Returns: 按从左到右、从上到下排列的拼图块。
    private static func slice(image: UIImage, rows: Int, columns: Int) -> [PuzzlePiece] {
        guard let cgImage = image.cgImage else { return [] }
        let width = cgImage.width, height = cgImage.height
        return (0..<(rows * columns)).compactMap { index in
            let row = index / columns, column = index % columns
            let x = column * width / columns, y = row * height / rows
            let nextX = (column + 1) * width / columns, nextY = (row + 1) * height / rows
            guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: nextX - x, height: nextY - y)) else { return nil }
            return PuzzlePiece(id: index, image: UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation))
        }
    }
}
