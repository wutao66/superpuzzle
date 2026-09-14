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
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self), let imageData = data, let image = UIImage(data: imageData) else { return }
            sourceImage = image
        }
    }

    /// 构建相册与难度设置页面。
    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("YOUR IMAGE · YOUR PACE").font(.caption2.monospaced()).foregroundStyle(.secondary).padding(.top, 42)
                Text("拼出属于你的\n完整画面").font(.system(size: 48, weight: .bold, design: .rounded)).tracking(-2).padding(.top, 14)
                Text("选择一张照片，设定难度。拼图会根据照片比例自动切成大小合适的矩形。").foregroundStyle(.secondary).padding(.top, 18)
                photoPicker.padding(.top, 30)
                difficultyPicker.padding(.top, 30)
                Button(action: beginGame) { Label("开始拼图", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 16) }.buttonStyle(.borderedProminent).tint(.black).disabled(sourceImage == nil).padding(.top, 28)
            }.padding(.horizontal, 22).padding(.bottom, 35)
        }.background(Color(.systemGroupedBackground))
    }

    /// 构建顶部品牌栏。
    private var header: some View { HStack { Text("▦  SUPER PUZZLE").font(.caption.bold().monospaced()); Spacer(); Text("把一张照片，变成一场专注").font(.caption2).foregroundStyle(.secondary) } }
    /// 构建相册选择区域。
    private var photoPicker: some View { PhotosPicker(selection: $selectedPhoto, matching: .images) { ZStack { RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.secondary).frame(height: 230); if let sourceImage { Image(uiImage: sourceImage).resizable().scaledToFit().frame(maxHeight: 205).clipShape(RoundedRectangle(cornerRadius: 7)) } else { VStack(spacing: 10) { Image(systemName: "plus").font(.largeTitle).foregroundStyle(.green); Text("选择一张图片").font(.headline); Text("支持 JPG、PNG、HEIC").font(.caption).foregroundStyle(.secondary) } } } }.buttonStyle(.plain) }
    /// 构建难度选择列表。
    private var difficultyPicker: some View { VStack(spacing: 0) { HStack { Text("选择难度").font(.headline); Spacer(); Text("\(model.difficulty.pieceCount) 片").font(.caption.monospaced()).foregroundStyle(.secondary) }.padding(.bottom, 12); ForEach(PuzzleDifficulty.allCases) { difficulty in Button { model.difficulty = difficulty } label: { HStack { Text(difficulty.rawValue).foregroundStyle(model.difficulty == difficulty ? Color.green : .primary).fontWeight(.semibold); Text("· \(difficulty.pieceCount) 片").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: model.difficulty == difficulty ? "checkmark.circle.fill" : "circle").foregroundStyle(model.difficulty == difficulty ? Color.green : .secondary) }.padding(.vertical, 13).overlay(alignment: .bottom) { Divider() } }.buttonStyle(.plain) } } }

    /// 构建拼图棋盘页面。
    private var gameView: some View { VStack(alignment: .leading, spacing: 0) { HStack { VStack(alignment: .leading) { Text("CURRENT PUZZLE").font(.caption2.monospaced()).foregroundStyle(.secondary); Text(model.isComplete ? "拼图完成！" : "\(model.difficulty.rawValue)模式").font(.largeTitle.bold()) }; Spacer(); Button("重新选择") { model.stopTimer(); showingGame = false }.font(.caption.monospaced()) }.padding(.bottom, 22); HStack { stat("难度", model.difficulty.rawValue); stat("完成度", "\(Int(Double(model.pieces.enumerated().filter { $0.offset == $0.element.id }.count) / Double(max(model.pieces.count, 1)) * 100))%"); Spacer(); stat("用时", formatTime(model.elapsedSeconds)); Button(action: model.shuffle) { Image(systemName: "arrow.clockwise") } }.padding(.vertical, 13).overlay(alignment: .top) { Divider() }; boardView.padding(.top, 22); Spacer() }.padding(22).background(Color(.systemGroupedBackground)) }
    /// 构建统计信息。
    private func stat(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2.monospaced()).foregroundStyle(.secondary); Text(value).font(.caption.bold()) } }
    /// 构建矩形拼图棋盘。
    private var boardView: some View { let grid = model.grid; return GeometryReader { proxy in LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: grid.columns), spacing: 1) { ForEach(Array(model.pieces.enumerated()), id: \.element.id) { index, piece in Button { model.tap(index: index) } label: { Image(uiImage: piece.image).resizable().scaledToFill().frame(width: proxy.size.width / CGFloat(grid.columns), height: proxy.size.width / CGFloat(grid.rows)).clipped().overlay(model.selectedIndex == index ? Color.green.opacity(0.38) : Color.clear) }.buttonStyle(.plain) } }.background(.black).clipShape(RoundedRectangle(cornerRadius: 8)) } }
    /// 开始当前设置的拼图。
    private func beginGame() { guard let sourceImage else { return }; model.start(with: sourceImage); showingGame = true }
    /// 格式化计时文本。
    private func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
