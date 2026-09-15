import SwiftUI

/// 拼图块单条边的形态，正值为凸榫，负值为凹槽，零值为外边框。
enum PuzzleEdge: CGFloat {
    case inward = -1
    case flat = 0
    case outward = 1

    /// 返回与当前边互补的相邻边。
    var opposite: PuzzleEdge {
        switch self {
        case .inward: return .outward
        case .flat: return .flat
        case .outward: return .inward
        }
    }
}

/// 描述一块拼图的四条边。
struct PuzzleEdges: Hashable {
    /// 拼图上边形态。
    let top: PuzzleEdge
    /// 拼图右边形态。
    let right: PuzzleEdge
    /// 拼图下边形态。
    let bottom: PuzzleEdge
    /// 拼图左边形态。
    let left: PuzzleEdge
}

/// 使用贝塞尔曲线绘制带凸榫和凹槽的经典拼图轮廓。
struct PuzzlePieceShape: Shape {
    /// 当前拼图的四条边。
    let edges: PuzzleEdges

    /// 在指定矩形中生成拼图轮廓路径。
    /// - Parameter rect: 包含凸榫留白的完整绘制区域。
    /// - Returns: 可用于裁剪、描边和点击检测的路径。
    func path(in rect: CGRect) -> Path {
        let pieceWidth = rect.width / 1.36
        let pieceHeight = rect.height / 1.36
        let tabX = pieceWidth * 0.18
        let tabY = pieceHeight * 0.18
        let minX = rect.minX + tabX
        let minY = rect.minY + tabY
        let maxX = minX + pieceWidth
        let maxY = minY + pieceHeight
        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        addHorizontalEdge(to: &path, from: minX, to: maxX, y: minY, tab: -tabY * edges.top.rawValue)
        addVerticalEdge(to: &path, from: minY, to: maxY, x: maxX, tab: tabX * edges.right.rawValue)
        addHorizontalEdge(to: &path, from: maxX, to: minX, y: maxY, tab: tabY * edges.bottom.rawValue)
        addVerticalEdge(to: &path, from: maxY, to: minY, x: minX, tab: -tabX * edges.left.rawValue)
        path.closeSubpath()
        return path
    }

    /// 添加一条带中央榫槽的水平边。
    /// - Parameters:
    ///   - path: 正在构建的路径。
    ///   - start: 水平起点。
    ///   - end: 水平终点。
    ///   - y: 基准纵坐标。
    ///   - tab: 榫槽突出方向和距离。
    private func addHorizontalEdge(to path: inout Path, from start: CGFloat, to end: CGFloat, y: CGFloat, tab: CGFloat) {
        let length = end - start
        guard tab != 0 else { path.addLine(to: CGPoint(x: end, y: y)); return }
        path.addLine(to: CGPoint(x: start + length * 0.34, y: y))
        path.addCurve(to: CGPoint(x: start + length * 0.43, y: y + tab * 0.22), control1: CGPoint(x: start + length * 0.40, y: y), control2: CGPoint(x: start + length * 0.41, y: y + tab * 0.08))
        path.addCurve(to: CGPoint(x: start + length * 0.50, y: y + tab), control1: CGPoint(x: start + length * 0.39, y: y + tab * 0.55), control2: CGPoint(x: start + length * 0.43, y: y + tab))
        path.addCurve(to: CGPoint(x: start + length * 0.57, y: y + tab * 0.22), control1: CGPoint(x: start + length * 0.57, y: y + tab), control2: CGPoint(x: start + length * 0.61, y: y + tab * 0.55))
        path.addCurve(to: CGPoint(x: start + length * 0.66, y: y), control1: CGPoint(x: start + length * 0.59, y: y + tab * 0.08), control2: CGPoint(x: start + length * 0.60, y: y))
        path.addLine(to: CGPoint(x: end, y: y))
    }

    /// 添加一条带中央榫槽的垂直边。
    /// - Parameters:
    ///   - path: 正在构建的路径。
    ///   - start: 垂直起点。
    ///   - end: 垂直终点。
    ///   - x: 基准横坐标。
    ///   - tab: 榫槽突出方向和距离。
    private func addVerticalEdge(to path: inout Path, from start: CGFloat, to end: CGFloat, x: CGFloat, tab: CGFloat) {
        let length = end - start
        guard tab != 0 else { path.addLine(to: CGPoint(x: x, y: end)); return }
        path.addLine(to: CGPoint(x: x, y: start + length * 0.34))
        path.addCurve(to: CGPoint(x: x + tab * 0.22, y: start + length * 0.43), control1: CGPoint(x: x, y: start + length * 0.40), control2: CGPoint(x: x + tab * 0.08, y: start + length * 0.41))
        path.addCurve(to: CGPoint(x: x + tab, y: start + length * 0.50), control1: CGPoint(x: x + tab * 0.55, y: start + length * 0.39), control2: CGPoint(x: x + tab, y: start + length * 0.43))
        path.addCurve(to: CGPoint(x: x + tab * 0.22, y: start + length * 0.57), control1: CGPoint(x: x + tab, y: start + length * 0.57), control2: CGPoint(x: x + tab * 0.55, y: start + length * 0.61))
        path.addCurve(to: CGPoint(x: x, y: start + length * 0.66), control1: CGPoint(x: x + tab * 0.08, y: start + length * 0.59), control2: CGPoint(x: x, y: start + length * 0.60))
        path.addLine(to: CGPoint(x: x, y: end))
    }
}
