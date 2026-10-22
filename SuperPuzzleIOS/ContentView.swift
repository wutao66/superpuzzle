import PhotosUI
import SwiftUI

/// 应用支持的显示语言，并提供系统语言默认值。
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var shortName: String { self == .chinese ? "中文" : "EN" }
    var locale: Locale { Locale(identifier: rawValue) }

    static var systemDefault: Self {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }

    func difficultyTitle(_ difficulty: PuzzleDifficulty) -> String {
        switch difficulty {
        case .easy: return text("简单", "Easy")
        case .normal: return text("普通", "Normal")
        case .hard: return text("困难", "Hard")
        case .nightmare: return text("噩梦", "Nightmare")
        case .hell: return text("地狱", "Hell")
        }
    }
}

/// Super Puzzle 的相册选择、难度选择和棋盘界面。
@MainActor
struct ContentView: View {
    /// 拼图状态对象。
    @StateObject private var model = PuzzleViewModel()
    /// 视频帧直接交给绘图视图，避免播放时重新计算整个棋盘。
    @State private var video = PuzzleVideoController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isImporting = false
    @State private var importError: String?
    /// 系统相册选择器返回值。
    @State private var selectedPhoto: PhotosPickerItem?
    /// 用户选中的原图。
    @State private var sourceImage: UIImage?
    /// 是否显示棋盘页面。
    @State private var showingGame = false
    /// 只在本局完成时展示一次固定成绩。
    @State private var completion: PuzzleCompletionResult?
    @State private var resumeVideoAfterCompletion = false
    /// 仅在开始拼图或请求提示时重置独立棋盘的变换。
    @State private var boardTransformID = UUID()
    /// 长按拖动期间的拼图位置，手势取消或结束时自动清空。
    @GestureState private var pieceDrag: (index: Int, translation: CGSize)?
    /// 用户选择的界面语言；首次启动时使用手机系统语言。
    @AppStorage("app.language") private var languageCode = AppLanguage.systemDefault.rawValue

    /// 当前有效语言。
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .english }

    /// 构建应用主界面。
    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if showingGame { gameView } else { setupView }
                }
                .navigationBarHidden(true)
            }
            .disabled(completion != nil)
            .accessibilityHidden(completion != nil)
            if let completion {
                PuzzleCompletionView(result: completion, language: language, onViewPuzzle: dismissCompletion) {
                    self.completion = nil
                    resumeVideoAfterCompletion = false
                    beginGame()
                }
                .zIndex(10)
            }
        }
        .onChange(of: model.isComplete) { complete in
            guard complete, showingGame else { completion = nil; return }
            completion = PuzzleCompletionResult(elapsedSeconds: model.elapsedSeconds,
                                                pieceCount: model.pieces.count, difficulty: model.difficulty)
            resumeVideoAfterCompletion = video.isPlaying
            video.pause()
            resetBoardTransform()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            await importSelection(selectedPhoto)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { video.pause() }
        }
        .onDisappear { video.reset(); model.stopTimer() }
        .alert(language.text("无法导入", "Unable to Import"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(language.text("好", "OK"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? language.text("请重新选择照片或视频。", "Please choose another photo or video."))
        }
        .environment(\.locale, language.locale)
        .preferredColorScheme(.dark)
    }

    /// 构建相册与难度设置页面。
    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(language.text("耐心的艺术", "THE ART OF PATIENCE")).font(.caption2.monospaced()).foregroundStyle(Color.puzzleBrass).padding(.top, 48)
                Text(language.text("把记忆\n拼回来", "PIECE THE\nMEMORY BACK")).font(.system(size: 48, weight: .semibold, design: .serif)).foregroundStyle(Color.puzzleIvory).padding(.top, 14)
                Text(language.text("从相册选一段记忆，在木桌上慢慢还原它。", "Choose a memory from your library and piece it back together.")).foregroundStyle(Color.puzzleMuted).padding(.top, 18)
                photoPicker.padding(.top, 30)
                if video.hasVideo {
                    PuzzleVideoControls(video: video, language: language).padding(.top, 16)
                }
                difficultyPicker.padding(.top, 30)
                Button(action: beginGame) { HStack { Text(language.text("开始拼图", "Start Puzzle")); Spacer(); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity) }.buttonStyle(BrassButtonStyle()).disabled(sourceImage == nil || isImporting).opacity(sourceImage == nil || isImporting ? 0.45 : 1).padding(.top, 28)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 22)
            .padding(.bottom, 35)
            .frame(maxWidth: .infinity)
        }.background { WoodTexture(tone: .walnut).ignoresSafeArea() }
    }

    /// 构建顶部品牌栏。
    private var header: some View {
        HStack {
            NavigationLink {
                LegalView(language: language)
            } label: {
                Image(systemName: "doc.text")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.puzzleIvory)
            .accessibilityLabel(language.text("隐私协议与用户协议", "Privacy Policy and User Agreement"))

            Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(Color.puzzleBrass)
            Text("SUPER PUZZLE").font(.caption.bold().monospaced()).foregroundStyle(Color.puzzleIvory)
            Spacer()
            Menu {
                Picker(language.text("语言", "Language"), selection: $languageCode) {
                    Text("中文").tag(AppLanguage.chinese.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }
            } label: {
                Label(language.shortName, systemImage: "globe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.puzzleIvory)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel(language.text("语言", "Language"))
        }
        .padding(.top, 18)
    }
    /// 照片与视频共用相册入口，视频预览与拼图共用播放控制器。
    private var photoPicker: some View {
        let preview = mediaPreview
        return PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) { preview }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("选择照片或视频", "Choose a photo or video"))
    }

    private var mediaPreview: some View {
        ZStack {
            WoodTexture(tone: .oak)
            RoundedRectangle(cornerRadius: 5).fill(Color.puzzleCharcoal.opacity(0.88)).padding(11)
            if isImporting {
                ProgressView(language.text("正在导入…", "Importing…")).tint(Color.puzzleBrass).foregroundStyle(Color.puzzleIvory)
            } else if video.hasVideo {
                PuzzleVideoPreview(video: video).padding(18)
                Image(systemName: "video.fill")
                    .foregroundStyle(Color.puzzleIvory)
                    .padding(8)
                    .background(Color.puzzleCharcoal.opacity(0.8))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(20)
            } else if let sourceImage {
                Image(uiImage: sourceImage).resizable().scaledToFit().frame(maxHeight: mediaPreviewHeight - 45).padding(18)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(Color.puzzleBrass)
                    Text(language.text("选择照片或视频", "Choose a Photo or Video")).font(.headline).foregroundStyle(Color.puzzleIvory)
                    Text(language.text("照片 · 视频", "PHOTO · VIDEO")).font(.caption2.monospaced()).foregroundStyle(Color.puzzleMuted)
                }
            }
        }
        .frame(height: mediaPreviewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.puzzleBrass.opacity(0.38), lineWidth: 1) }
        .shadow(color: .black.opacity(0.42), radius: 16, y: 9)
    }

    /// 根据当前窗口尺寸级别调整素材预览高度。
    private var mediaPreviewHeight: CGFloat { horizontalSizeClass == .regular ? 320 : 250 }

    /// 构建难度选择列表。
    private var difficultyPicker: some View { VStack(spacing: 0) { HStack { Text(language.text("选择难度", "Choose Difficulty")).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(Color.puzzleIvory); Spacer(); Text(language.text("\(model.difficulty.pieceCount) 块拼图", "\(model.difficulty.pieceCount) PIECES")).font(.caption.monospaced()).foregroundStyle(Color.puzzleBrass) }.padding(.bottom, 12); ForEach(PuzzleDifficulty.allCases) { difficulty in Button { model.difficulty = difficulty } label: { HStack { Text(language.difficultyTitle(difficulty)).foregroundStyle(model.difficulty == difficulty ? Color.puzzleBrass : Color.puzzleIvory).fontWeight(.semibold); Text(language.text("· \(difficulty.pieceCount) 片", "· \(difficulty.pieceCount) pieces")).font(.caption).foregroundStyle(Color.puzzleMuted); Spacer(); Image(systemName: model.difficulty == difficulty ? "checkmark.circle.fill" : "circle").foregroundStyle(model.difficulty == difficulty ? Color.puzzleBrass : Color.puzzleMuted) }.padding(.vertical, 13).overlay(alignment: .bottom) { Color.puzzleBrass.opacity(0.24).frame(height: 1) } }.buttonStyle(.plain) } } }

    /// 构建拼图棋盘页面。
    private var gameView: some View {
        GeometryReader { proxy in
            ScrollView {
                if usesWideGameLayout(proxy.size) {
                    wideGameLayout(in: proxy.size)
                } else {
                    compactGameLayout
                }
            }
        }
        .background { WoodTexture(tone: .walnut).ignoresSafeArea() }
    }

    /// 窄窗口和 iPad 竖屏使用的纵向棋盘布局。
    private var compactGameLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            gameHeader
            gameStats(vertical: false).padding(.top, 22)
            gameAuxiliaryControls
            puzzleTrayView.padding(.top, 22)
        }
        .frame(maxWidth: 1_100)
        .padding(18)
        .frame(maxWidth: .infinity)
    }

    /// iPad 横屏宽窗口使用的控制栏与棋盘并排布局。
    private func wideGameLayout(in size: CGSize) -> some View {
        let sidebarWidth: CGFloat = 320
        let spacing: CGFloat = 24
        let availableBoardWidth = max(320, size.width - sidebarWidth - spacing - 36)
        let availableBoardHeight = max(320, size.height - 36)
        let boardWidth = min(availableBoardWidth, availableBoardHeight * model.imageAspect)
        let boardHeight = boardWidth / max(model.imageAspect, 0.01)

        return HStack(alignment: .top, spacing: spacing) {
            VStack(alignment: .leading, spacing: 0) {
                gameHeader
                gameStats(vertical: true).padding(.top, 22)
                gameAuxiliaryControls
            }
            .frame(width: sidebarWidth)

            puzzleTrayView
                .frame(width: boardWidth, height: boardHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: size.height, alignment: .top)
    }

    /// 宽度和横竖比例同时满足时启用 iPad 横屏双栏。
    private func usesWideGameLayout(_ size: CGSize) -> Bool {
        size.width >= 1_100 && size.width > size.height
    }

    /// 构建游戏标题与退出按钮。
    private var gameHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(video.hasVideo ? language.text("视频拼图", "VIDEO PUZZLE") : language.text("当前拼图", "CURRENT PUZZLE"))
                    .font(.caption2.monospaced()).foregroundStyle(Color.puzzleBrass)
                Text(model.isComplete ? language.text("拼图完成！", "Puzzle Complete!") : language.text("\(language.difficultyTitle(model.difficulty))模式", "\(language.difficultyTitle(model.difficulty)) Mode"))
                    .font(.system(size: 33, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.puzzleIvory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 12)
            Button {
                model.stopTimer()
                video.pause()
                showingGame = false
            } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
            .background(Color.puzzleCharcoal).clipShape(Circle()).accessibilityLabel(language.text("重新选择", "Choose Again"))
        }
    }

    /// 构建适合横向工具条或 iPad 侧栏的统计区域。
    @ViewBuilder
    private func gameStats(vertical: Bool) -> some View {
        let progress = "\(Int(Double(model.pieces.enumerated().filter { $0.offset == $0.element.id }.count) / Double(max(model.pieces.count, 1)) * 100))%"
        if vertical {
            VStack(spacing: 12) {
                HStack {
                    stat(language.text("难度", "Difficulty"), language.difficultyTitle(model.difficulty))
                    Spacer()
                    stat(language.text("完成度", "Progress"), progress)
                }
                Color.puzzleBrass.opacity(0.2).frame(height: 1)
                HStack {
                    stat(language.text("用时", "Time"), formatTime(model.elapsedSeconds))
                    Spacer()
                    shuffleButton
                }
            }
            .padding(14).background(Color.puzzleCharcoal.opacity(0.84)).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            HStack {
                stat(language.text("难度", "Difficulty"), language.difficultyTitle(model.difficulty))
                stat(language.text("完成度", "Progress"), progress)
                Spacer()
                stat(language.text("用时", "Time"), formatTime(model.elapsedSeconds))
                shuffleButton
            }
            .padding(13).background(Color.puzzleCharcoal.opacity(0.84)).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// 构建重新打乱按钮。
    private var shuffleButton: some View {
        Button(action: model.shuffle) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
            .foregroundStyle(Color.puzzleBrass).accessibilityLabel(language.text("重新打乱", "Shuffle Again"))
    }

    /// 构建视频与提示控制区域。
    private var gameAuxiliaryControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if video.hasVideo { PuzzleVideoControls(video: video, language: language).zIndex(2) }
            hintControls.zIndex(1)
        }
        .padding(.top, 16)
    }

    /// 提示入口与当前交换建议。
    private var hintControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                resetBoardTransform()
                model.showHint()
            } label: {
                Label(language.text("提示", "Hint"), systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.puzzleBrass)
            .background(Color.puzzleCharcoal.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(model.isComplete || model.pieces.isEmpty || pieceDrag != nil)
            .opacity(model.isComplete ? 0.45 : 1)
            .accessibilityHint(language.text("标出两块可交换的拼图，帮助一块归位", "Marks two pieces to swap so one moves into place"))

            if let hint = model.hint {
                let columns = model.grid.columns
                Text(language.text("交换标记 ①（第 \(hint.source / columns + 1) 行第 \(hint.source % columns + 1) 列）和 ②（第 \(hint.destination / columns + 1) 行第 \(hint.destination % columns + 1) 列），即可让 ① 归位。", "Swap marker ① (row \(hint.source / columns + 1), column \(hint.source % columns + 1)) with ② (row \(hint.destination / columns + 1), column \(hint.destination % columns + 1)) to move ① into place."))
                    .font(.subheadline)
                    .foregroundStyle(Color.puzzleIvory)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// 构建统计信息。
    private func stat(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2.monospaced()).foregroundStyle(Color.puzzleMuted); Text(value).font(.caption.bold()).foregroundStyle(Color.puzzleIvory) } }
    /// 构建可整体缩放和拖动的木质拼图盘。
    private var puzzleTrayView: some View {
        PuzzleTrayView(aspectRatio: model.imageAspect, resetID: boardTransformID, isDraggingPiece: pieceDrag != nil) {
            boardView
        }
    }

    /// 构建允许凸榫互相覆盖的异形拼图内容。
    private var boardView: some View {
        let grid = model.grid
        return GeometryReader { proxy in
            let cellWidth = proxy.size.width / CGFloat(grid.columns)
            let cellHeight = proxy.size.height / CGFloat(grid.rows)
            ZStack(alignment: .topLeading) {
                Color.puzzleCharcoal
                if video.hasVideo {
                    VideoPuzzleBoard(video: video, pieces: model.pieces, rows: grid.rows, columns: grid.columns,
                                     draggedIndex: pieceDrag?.index, translation: pieceDrag?.translation ?? .zero,
                                     selectedIndex: model.selectedIndex,
                                     hintedIndices: model.hint.map { [$0.source, $0.destination] } ?? [])
                        .allowsHitTesting(false)
                }
                ForEach(Array(model.pieces.enumerated()), id: \.element.id) { index, piece in
                    pieceArtwork(piece)
                        .frame(width: cellWidth * 1.36, height: cellHeight * 1.36)
                        .overlay {
                            PuzzlePieceShape(edges: piece.edges)
                                .stroke(model.selectedIndex == index ? Color.puzzleBrass : Color.white.opacity(0.35), lineWidth: model.selectedIndex == index ? 2 : 0.45)
                        }
                        .overlay {
                            if let hint = model.hint, index == hint.source || index == hint.destination {
                                PuzzlePieceShape(edges: piece.edges)
                                    .stroke(Color.puzzleBrass, lineWidth: 3)
                                Text(index == hint.source ? "①" : "②")
                                    .font(.system(size: min(22, min(cellWidth, cellHeight) * 0.7), weight: .bold))
                                    .foregroundStyle(Color.puzzleCharcoal)
                                    .background(Circle().fill(Color.puzzleIvory))
                            }
                        }
                        .contentShape(PuzzlePieceShape(edges: piece.edges))
                    .offset(pieceDrag?.index == index ? pieceDrag?.translation ?? .zero : .zero)
                    .highPriorityGesture(pieceGesture(index: index, cellWidth: cellWidth, cellHeight: cellHeight))
                    .accessibilityLabel(language.text("第 \(piece.id + 1) 块拼图", "Puzzle piece \(piece.id + 1)"))
                    .accessibilityHint(language.text("长按后拖到另一块拼图上交换，也可依次点选两块拼图", "Press and drag onto another piece to swap, or tap two pieces in sequence"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.tap(index: index) }
                    .position(x: (CGFloat(index % grid.columns) + 0.5) * cellWidth, y: (CGFloat(index / grid.columns) + 0.5) * cellHeight)
                    .zIndex(model.selectedIndex == index ? 10_000 : (model.hint?.source == index || model.hint?.destination == index ? 9_999 : Double(index)))
                }
            }
            .coordinateSpace(name: "puzzleBoard")
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .aspectRatio(model.imageAspect, contentMode: .fit)
    }
    /// 开始当前设置的拼图。
    private func beginGame() {
        guard let sourceImage, !isImporting else { return }
        resetBoardTransform()
        model.start(with: sourceImage, usesVideo: video.hasVideo)
        showingGame = true
        if video.hasVideo { video.play() }
    }

    @ViewBuilder
    private func pieceArtwork(_ piece: PuzzlePiece) -> some View {
        if video.hasVideo { Color.clear }
        else { Image(uiImage: piece.image).resizable() }
    }

    /// 只有当前相册选择能够提交结果，取消或失败时删除临时视频。
    private func importSelection(_ selection: PhotosPickerItem) async {
        isImporting = true
        sourceImage = nil
        importError = nil
        video.reset()
        defer { if selectedPhoto == selection { isImporting = false } }
        do {
            if selection.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let imported = try await selection.loadTransferable(type: ImportedPuzzleVideo.self) else {
                    throw PuzzleVideoSource.VideoError.unreadable
                }
                do {
                    let source = try await PuzzleVideoSource.prepare(url: imported.url)
                    try Task.checkCancellation()
                    guard selectedPhoto == selection else { throw CancellationError() }
                    video.configure(source)
                    sourceImage = UIImage(cgImage: source.poster)
                } catch {
                    PuzzleVideoController.removeImportedFile(at: imported.url)
                    throw error
                }
            } else {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { throw PuzzleVideoSource.VideoError.unreadable }
                try Task.checkCancellation()
                guard selectedPhoto == selection else { return }
                sourceImage = image
            }
        } catch is CancellationError {
            // 新选择接管页面，取消结果不向用户显示为错误。
        } catch {
            guard !Task.isCancelled, selectedPhoto == selection else { return }
            importError = language.text("无法读取所选照片或视频，请重新选择。", "The selected photo or video could not be read. Please choose another one.")
        }
    }
    /// 欣赏完整作品时恢复弹窗前的视频播放状态。
    private func dismissCompletion() {
        completion = nil
        if resumeVideoAfterCompletion, scenePhase == .active { video.play() }
        resumeVideoAfterCompletion = false
    }

    /// 格式化计时文本。
    private func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    /// 长按拾取后拖动拼图，松手时仅在棋盘有效格子内交换。
    private func pieceGesture(index: Int, cellWidth: CGFloat, cellHeight: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
            .onEnded { _ in model.pickUp(index: index) }
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("puzzleBoard")))
            .updating($pieceDrag) { value, state, _ in
                if case .second(true, let drag) = value {
                    state = (index, drag?.translation ?? .zero)
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      cellWidth > 0, cellHeight > 0,
                      drag.location.x >= 0, drag.location.y >= 0,
                      drag.location.x < cellWidth * CGFloat(model.grid.columns),
                      drag.location.y < cellHeight * CGFloat(model.grid.rows) else { return }
                let column = Int(drag.location.x / cellWidth)
                let row = Int(drag.location.y / cellHeight)
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.swap(from: index, to: row * model.grid.columns + column)
                }
            }
            .exclusively(before: TapGesture().onEnded { model.tap(index: index) })
    }

    /// 重置通知不会在拖动时触发整个页面刷新。
    private func resetBoardTransform() { boardTransformID = UUID() }
}

/// 变换状态局限于底盘；滑动和缩放不重新构建整页及数千个拼图手势。
@MainActor
private struct PuzzleTrayView<Content: View>: View {
    let aspectRatio: CGFloat
    let resetID: UUID
    let isDraggingPiece: Bool
    let content: Content
    @State private var boardScale: CGFloat = 1
    @State private var boardBaseScale: CGFloat = 1
    @State private var boardOffset: CGSize = .zero
    @State private var boardBaseOffset: CGSize = .zero

    init(aspectRatio: CGFloat, resetID: UUID, isDraggingPiece: Bool, @ViewBuilder content: () -> Content) {
        self.aspectRatio = aspectRatio
        self.resetID = resetID
        self.isDraggingPiece = isDraggingPiece
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let minimumScale: CGFloat = 1
            ZStack {
                content.padding(14)
            }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background { WoodTexture(tone: .oak) }
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.puzzleBrass.opacity(0.45), lineWidth: 1) }
                .background {
                    // 阴影使用静态底盘轮廓，不对每帧视频重新做阴影合成。
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.puzzleCharcoal)
                        .shadow(color: .black.opacity(0.48), radius: 18, y: 10)
                }
                .scaleEffect(boardScale)
                .offset(boardOffset)
                .simultaneousGesture(zoomGesture(minimumScale: minimumScale, viewport: proxy.size))
                .simultaneousGesture(panGesture(viewport: proxy.size))
                .onChange(of: proxy.size) { _ in resetTransform() }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        // 允许底盘与拼图一起超出原始尺寸；触摸仍限于棋盘区域，避免遮挡按钮。
        .contentShape(Rectangle())
        .onChange(of: resetID) { _ in
            resetTransform()
        }
    }

    /// 创建双指捏合缩放手势，并限制棋盘不能缩小到当前窗口底盘以下。
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
                guard !isDraggingPiece else { return }
                let proposed = CGSize(width: boardBaseOffset.width + value.translation.width, height: boardBaseOffset.height + value.translation.height)
                boardOffset = limitedOffset(proposed, scale: boardScale, viewport: viewport)
            }
            .onEnded { _ in
                guard !isDraggingPiece else { return }
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

    /// 在窗口尺寸或外部重置标识变化时恢复棋盘全览。
    private func resetTransform() {
        boardScale = 1
        boardBaseScale = 1
        boardOffset = .zero
        boardBaseOffset = .zero
    }
}

/// 协议页面可切换的文档类型。
private enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }
}

/// 协议正文中的标题与段落。
private struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

/// 展示离线应用的隐私协议和用户协议。
private struct LegalView: View {
    let language: AppLanguage
    @State private var document: LegalDocument = .privacy
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("返回", "Back"))

                Text(language.text("隐私与协议", "Privacy & Terms"))
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(Color.puzzleIvory)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Picker("", selection: $document) {
                Text(language.text("隐私协议", "Privacy Policy")).tag(LegalDocument.privacy)
                Text(language.text("用户协议", "User Agreement")).tag(LegalDocument.terms)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(documentTitle)
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.puzzleIvory)

                    Text(language.text("生效日期：2026年10月22日", "Effective date: October 22, 2026"))
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.puzzleBrass)

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(Color.puzzleIvory)
                            Text(section.body)
                                .font(.body)
                                .foregroundStyle(Color.puzzleMuted)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .background { WoodTexture(tone: .walnut).ignoresSafeArea() }
        .navigationBarHidden(true)
    }

    private var documentTitle: String {
        switch document {
        case .privacy: return language.text("隐私协议", "Privacy Policy")
        case .terms: return language.text("用户协议", "User Agreement")
        }
    }

    private var sections: [LegalSection] {
        switch (document, language) {
        case (.privacy, .chinese):
            return [
                LegalSection(title: "1. 概述", body: "Super Puzzle 是一款无需账号、无需联网的本地拼图应用。本 App 不主动建立网络连接，不运营服务器，也不会向开发者或第三方上传您的数据。"),
                LegalSection(title: "2. 不收集的信息", body: "本 App 不收集姓名、手机号、邮箱、账号、位置、通讯录、设备标识、使用分析、广告标识或行为追踪信息，不包含广告或第三方分析服务。"),
                LegalSection(title: "3. 照片与视频", body: "只有在您主动使用系统照片选择器时，本 App 才能读取您明确选择的照片或视频。素材仅在设备本地用于预览、切片和拼图。照片在运行期间保存在应用内存中；所选视频会复制到 App 的临时目录供本地播放，并在更换素材或离开相关页面后删除。素材不会上传。"),
                LegalSection(title: "4. 本地存储", body: "您选择的界面语言会保存在设备的 App 偏好设置中。拼图进度和所选媒体不会同步到服务器，本 App 也不提供云端备份。卸载 App 时，系统会移除其本地数据。"),
                LegalSection(title: "5. 系统权限", body: "本 App 通过 Apple 提供的系统照片选择器获取单次选择的媒体，不要求访问完整照片图库。系统和 App Store 可能依照 Apple 自身政策处理诊断、购买或分发信息，该等处理不由本 App 控制。"),
                LegalSection(title: "6. 儿童隐私", body: "由于本 App 不收集或传输个人信息，因此也不会主动收集儿童的个人信息。监护人仍应根据实际情况指导儿童使用设备和媒体内容。"),
                LegalSection(title: "7. 协议更新", body: "如功能或数据处理方式发生变化，本协议将随 App 更新，并在本页面说明新的生效日期。")
            ]
        case (.privacy, .english):
            return [
                LegalSection(title: "1. Overview", body: "Super Puzzle is a local puzzle app that requires no account and no network connection. The App does not initiate network connections, operate a server, or upload your data to the developer or third parties."),
                LegalSection(title: "2. Information We Do Not Collect", body: "The App does not collect names, phone numbers, email addresses, accounts, locations, contacts, device identifiers, analytics, advertising identifiers, or tracking data. It contains no advertising or third-party analytics services."),
                LegalSection(title: "3. Photos and Videos", body: "The App reads a photo or video only after you explicitly select it through Apple's system photo picker. Media is processed locally for preview, slicing, and puzzle play. Photos remain in app memory while in use. A selected video is copied to the App's temporary directory for local playback and deleted when you replace the media or leave the related experience. Media is never uploaded."),
                LegalSection(title: "4. Local Storage", body: "Your language choice is stored in the App's local preferences. Puzzle progress and selected media are not synchronized to a server, and the App provides no cloud backup. The system removes local App data when the App is uninstalled."),
                LegalSection(title: "5. System Services", body: "The App uses Apple's system photo picker to receive only the media you select and does not request full photo-library access. Apple and the App Store may process diagnostic, purchase, or distribution information under their own policies; that processing is outside this App's control."),
                LegalSection(title: "6. Children's Privacy", body: "Because the App does not collect or transmit personal information, it does not knowingly collect children's personal information. Guardians should still supervise device and media use as appropriate."),
                LegalSection(title: "7. Policy Updates", body: "If the App's features or data practices change, this policy will be updated with the App and will show a new effective date on this page.")
            ]
        case (.terms, .chinese):
            return [
                LegalSection(title: "1. 接受协议", body: "下载、安装或使用 Super Puzzle，即表示您同意本用户协议。若您不同意，请停止使用并卸载本 App。"),
                LegalSection(title: "2. 服务内容", body: "本 App 提供本地照片和视频拼图功能，无需账号或网络服务。功能可能因设备性能、系统版本以及所选媒体的格式和大小而有所差异。"),
                LegalSection(title: "3. 用户内容", body: "您保留所选照片和视频的全部权利。您应确保有权在设备上使用相关内容，并对内容的合法性负责。本 App 不接收、托管或发布您的媒体。"),
                LegalSection(title: "4. 合理使用", body: "请勿利用本 App 从事违法、侵权或危害设备安全的活动，也不得以破坏 App 正常运行的方式使用本 App。"),
                LegalSection(title: "5. 本地数据责任", body: "本 App 不是媒体存储或备份工具。请自行保存原始照片和视频。因卸载 App、清理设备空间、系统故障或设备损坏造成的本地状态丢失，本 App 无法恢复。"),
                LegalSection(title: "6. 免责声明", body: "本 App 按现状提供。在适用法律允许的范围内，不保证在所有设备或媒体上始终无中断、无错误运行。"),
                LegalSection(title: "7. 协议变更", body: "本协议可能随功能调整而更新。继续使用更新后的 App，即表示您接受更新后的协议。协议按适用法律解释。")
            ]
        case (.terms, .english):
            return [
                LegalSection(title: "1. Acceptance", body: "By downloading, installing, or using Super Puzzle, you agree to this User Agreement. If you do not agree, stop using and uninstall the App."),
                LegalSection(title: "2. Service", body: "The App provides local photo and video puzzle features without an account or network service. Functionality may vary with device performance, system version, and the format or size of selected media."),
                LegalSection(title: "3. Your Content", body: "You retain all rights to the photos and videos you select. You are responsible for ensuring that you have the right to use that content on your device and that it is lawful. The App does not receive, host, or publish your media."),
                LegalSection(title: "4. Acceptable Use", body: "Do not use the App for unlawful, infringing, or device-compromising activity, or in a manner intended to disrupt its normal operation."),
                LegalSection(title: "5. Local Data", body: "The App is not a media storage or backup service. Keep your original photos and videos separately. The App cannot recover local state lost through uninstallation, storage cleanup, system failure, or device damage."),
                LegalSection(title: "6. Disclaimer", body: "The App is provided as is. To the extent permitted by applicable law, uninterrupted or error-free operation on every device or with every media file is not guaranteed."),
                LegalSection(title: "7. Changes", body: "This Agreement may be updated as features change. Continued use of an updated version means that you accept the revised Agreement. This Agreement is interpreted under applicable law.")
            ]
        }
    }
}
