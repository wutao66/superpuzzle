import PhotosUI
import SwiftUI

/// Super Puzzle 的相册选择、难度选择和棋盘界面。
struct ContentView: View {
    /// 拼图状态对象。
    @StateObject private var model = PuzzleViewModel()
    /// 系统相册选择器返回值。
    @State private var selectedPhoto: PhotosPickerItem?
    /// 用户选中的原图。
    @State private var sourceImage: UIImage?
    /// 是否显示棋盘页面。
    @State private var showingGame = false
    /// 拼图棋盘当前缩放比例。
    @State private var boardScale: CGFloat = 1
    /// 本次捏合开始前的缩放比例。
    @State private var boardBaseScale: CGFloat = 1
    /// 拼图棋盘当前拖动偏移。
    @State private var boardOffset: CGSize = .zero
    /// 本次拖动开始前的棋盘偏移。
    @State private var boardBaseOffset: CGSize = .zero

    /// 构建应用主界面。
    var body: some View {
        NavigationStack {
            Group {
                if showingGame { gameView } else { setupView }
            }
                .navigationBarHidden(true)
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            sourceImage = image
        }
        .preferredColorScheme(.dark)
    }

    /// 构建相册与难度设置页面。
    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("THE ART OF PATIENCE").font(.caption2.monospaced()).foregroundStyle(Color.puzzleBrass).padding(.top, 48)
                Text("把记忆\n拼回来").font(.system(size: 48, weight: .semibold, design: .serif)).foregroundStyle(Color.puzzleIvory).padding(.top, 14)
                Text("从相册选一段记忆，在木桌上慢慢还原它。").foregroundStyle(Color.puzzleMuted).padding(.top, 18)
                photoPicker.padding(.top, 30)
                difficultyPicker.padding(.top, 30)
                Button(action: beginGame) { HStack { Text("开始拼图"); Spacer(); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity) }.buttonStyle(BrassButtonStyle()).disabled(sourceImage == nil).opacity(sourceImage == nil ? 0.45 : 1).padding(.top, 28)
            }.padding(.horizontal, 22).padding(.bottom, 35)
        }.background { WoodTexture(tone: .walnut).ignoresSafeArea() }
    }

    /// 构建顶部品牌栏。
    private var header: some View { HStack { Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(Color.puzzleBrass); Text("SUPER PUZZLE").font(.caption.bold().monospaced()).foregroundStyle(Color.puzzleIvory); Spacer(); Text("HANDCRAFTED").font(.caption2.monospaced()).foregroundStyle(Color.puzzleMuted) }.padding(.top, 18) }
    /// 构建相册选择区域。
    private var photoPicker: some View { PhotosPicker(selection: $selectedPhoto, matching: .images) { ZStack { WoodTexture(tone: .oak); RoundedRectangle(cornerRadius: 5).fill(Color.puzzleCharcoal.opacity(0.88)).padding(11); if let sourceImage { Image(uiImage: sourceImage).resizable().scaledToFit().frame(maxHeight: 205).padding(18).shadow(color: .black.opacity(0.5), radius: 12, y: 7) } else { VStack(spacing: 10) { Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(Color.puzzleBrass); Text("选择一张照片").font(.headline).foregroundStyle(Color.puzzleIvory); Text("JPG · PNG · HEIC").font(.caption2.monospaced()).foregroundStyle(Color.puzzleMuted) } } }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 7)).overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.puzzleBrass.opacity(0.38), lineWidth: 1) }.shadow(color: .black.opacity(0.42), radius: 16, y: 9) }.buttonStyle(.plain) }
    /// 构建难度选择列表。
    private var difficultyPicker: some View { VStack(spacing: 0) { HStack { Text("选择难度").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(Color.puzzleIvory); Spacer(); Text("\(model.difficulty.pieceCount) PIECES").font(.caption.monospaced()).foregroundStyle(Color.puzzleBrass) }.padding(.bottom, 12); ForEach(PuzzleDifficulty.allCases) { difficulty in Button { model.difficulty = difficulty } label: { HStack { Text(difficulty.rawValue).foregroundStyle(model.difficulty == difficulty ? Color.puzzleBrass : Color.puzzleIvory).fontWeight(.semibold); Text("· \(difficulty.pieceCount) 片").font(.caption).foregroundStyle(Color.puzzleMuted); Spacer(); Image(systemName: model.difficulty == difficulty ? "checkmark.circle.fill" : "circle").foregroundStyle(model.difficulty == difficulty ? Color.puzzleBrass : Color.puzzleMuted) }.padding(.vertical, 13).overlay(alignment: .bottom) { Color.puzzleBrass.opacity(0.24).frame(height: 1) } }.buttonStyle(.plain) } } }

    /// 构建拼图棋盘页面。
    private var gameView: some View { VStack(alignment: .leading, spacing: 0) { HStack { VStack(alignment: .leading) { Text("CURRENT PUZZLE").font(.caption2.monospaced()).foregroundStyle(Color.puzzleBrass); Text(model.isComplete ? "拼图完成！" : "\(model.difficulty.rawValue)模式").font(.system(size: 33, weight: .semibold, design: .serif)).foregroundStyle(Color.puzzleIvory) }; Spacer(); Button { model.stopTimer(); showingGame = false } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }.background(Color.puzzleCharcoal).clipShape(Circle()).accessibilityLabel("重新选择") }.padding(.bottom, 22); HStack { stat("难度", model.difficulty.rawValue); stat("完成度", "\(Int(Double(model.pieces.enumerated().filter { $0.offset == $0.element.id }.count) / Double(max(model.pieces.count, 1)) * 100))%"); Spacer(); stat("用时", formatTime(model.elapsedSeconds)); Button(action: model.shuffle) { Image(systemName: "arrow.clockwise").frame(width: 38, height: 38) }.foregroundStyle(Color.puzzleBrass).accessibilityLabel("重新打乱") }.padding(13).background(Color.puzzleCharcoal.opacity(0.84)).clipShape(RoundedRectangle(cornerRadius: 6)); boardView.padding(14).background { WoodTexture(tone: .oak) }.clipShape(RoundedRectangle(cornerRadius: 7)).overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.puzzleBrass.opacity(0.45), lineWidth: 1) }.shadow(color: .black.opacity(0.48), radius: 18, y: 10).padding(.top, 22); Spacer() }.padding(18).background { WoodTexture(tone: .walnut).ignoresSafeArea() } }
    /// 构建统计信息。
    private func stat(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2.monospaced()).foregroundStyle(Color.puzzleMuted); Text(value).font(.caption.bold()).foregroundStyle(Color.puzzleIvory) } }
    /// 构建允许凸榫互相覆盖的异形拼图棋盘。
    private var boardView: some View {
        let grid = model.grid
        return GeometryReader { proxy in
            let cellWidth = proxy.size.width / CGFloat(grid.columns)
            let cellHeight = proxy.size.height / CGFloat(grid.rows)
            let minimumScale = min(1, UIScreen.main.bounds.width * 0.8 / proxy.size.width)
            ZStack(alignment: .topLeading) {
                Color.puzzleCharcoal
                ForEach(Array(model.pieces.enumerated()), id: \.element.id) { index, piece in
                    Button { model.tap(index: index) } label: {
                        Image(uiImage: piece.image)
                            .resizable()
                            .frame(width: cellWidth * 1.36, height: cellHeight * 1.36)
                            .overlay {
                                PuzzlePieceShape(edges: piece.edges)
                                    .stroke(model.selectedIndex == index ? Color.puzzleBrass : Color.white.opacity(0.35), lineWidth: model.selectedIndex == index ? 2 : 0.45)
                            }
                            .contentShape(PuzzlePieceShape(edges: piece.edges))
                    }
                    .buttonStyle(.plain)
                    .position(x: (CGFloat(index % grid.columns) + 0.5) * cellWidth, y: (CGFloat(index / grid.columns) + 0.5) * cellHeight)
                    .zIndex(model.selectedIndex == index ? 10_000 : Double(index))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(boardScale)
            .offset(boardOffset)
            .simultaneousGesture(zoomGesture(minimumScale: minimumScale, viewport: proxy.size))
            .simultaneousGesture(panGesture(viewport: proxy.size))
        }
        .aspectRatio(model.imageAspect, contentMode: .fit)
        .clipped()
    }
    /// 开始当前设置的拼图。
    private func beginGame() { guard let sourceImage else { return }; resetBoardTransform(); model.start(with: sourceImage); showingGame = true }
    /// 格式化计时文本。
    private func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    /// 创建双指捏合缩放手势，并限制棋盘最小为屏幕宽度的百分之八十。
    /// - Parameters:
    ///   - minimumScale: 根据当前屏幕和棋盘宽度计算出的最小缩放比例。
    ///   - viewport: 棋盘可视区域尺寸。
    /// - Returns: 可附加到棋盘上的缩放手势。
    private func zoomGesture(minimumScale: CGFloat, viewport: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                boardScale = min(5, max(minimumScale, boardBaseScale * value))
                boardOffset = limitedOffset(boardOffset, scale: boardScale, viewport: viewport)
            }
            .onEnded { _ in
                boardBaseScale = boardScale
                boardOffset = limitedOffset(boardOffset, scale: boardScale, viewport: viewport)
                boardBaseOffset = boardOffset
            }
    }

    /// 创建棋盘拖动手势，供放大后浏览不同区域。
    /// - Parameter viewport: 棋盘可视区域尺寸。
    /// - Returns: 可附加到棋盘上的拖动手势。
    private func panGesture(viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let proposed = CGSize(width: boardBaseOffset.width + value.translation.width, height: boardBaseOffset.height + value.translation.height)
                boardOffset = limitedOffset(proposed, scale: boardScale, viewport: viewport)
            }
            .onEnded { _ in
                boardOffset = limitedOffset(boardOffset, scale: boardScale, viewport: viewport)
                boardBaseOffset = boardOffset
            }
    }

    /// 将拖动范围限制在放大后的棋盘边界内，避免棋盘完全移出屏幕。
    /// - Parameters:
    ///   - offset: 用户手势产生的目标偏移。
    ///   - scale: 当前缩放比例。
    ///   - viewport: 棋盘可视区域尺寸。
    /// - Returns: 限制在有效范围内的偏移。
    private func limitedOffset(_ offset: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let maximumX = max(0, viewport.width * (scale - 1) / 2)
        let maximumY = max(0, viewport.height * (scale - 1) / 2)
        return CGSize(width: min(max(offset.width, -maximumX), maximumX), height: min(max(offset.height, -maximumY), maximumY))
    }

    /// 恢复棋盘的默认缩放和居中位置。
    private func resetBoardTransform() {
        boardScale = 1
        boardBaseScale = 1
        boardOffset = .zero
        boardBaseOffset = .zero
    }
}
