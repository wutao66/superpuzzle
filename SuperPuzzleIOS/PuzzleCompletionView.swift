import SwiftUI

/// 完成时固定结果，后续重新开始或计时器回调不会改变已展示的成绩。
struct PuzzleCompletionResult {
    let elapsedSeconds: Int
    let pieceCount: Int
    let difficulty: PuzzleDifficulty

    func durationText(language: AppLanguage) -> String {
        let seconds = max(0, elapsedSeconds)
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let remainder = seconds % 60
        if hours > 0 {
            return language.text("\(hours)小时 \(minutes)分 \(remainder)秒", "\(hours)h \(minutes)m \(remainder)s")
        }
        if minutes > 0 {
            return language.text("\(minutes)分 \(remainder)秒", "\(minutes)m \(remainder)s")
        }
        return language.text("\(remainder)秒", "\(remainder)s")
    }
}

/// 轻量完成弹窗，庆祝动画只播放一次，不循环刷新棋盘。
struct PuzzleCompletionView: View {
    let result: PuzzleCompletionResult
    let language: AppLanguage
    let onViewPuzzle: () -> Void
    let onPlayAgain: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.7).ignoresSafeArea()
                if !reduceMotion {
                    CompletionConfetti().ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                }
                ScrollView {
                    card
                        .frame(maxWidth: 380)
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            if reduceMotion { revealed = true }
            else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.76)) { revealed = true }
            }
            titleFocused = true
        }
        .accessibilityAction(.escape, onViewPuzzle)
    }

    private var card: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.puzzleBrass.opacity(0.13))
                Circle().stroke(Color.puzzleBrass.opacity(0.35), lineWidth: 1).padding(5)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.puzzleBrass)
                    .scaleEffect(revealed ? 1 : 0.6)
                    .rotationEffect(.degrees(revealed || reduceMotion ? 0 : -12))
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)

            Text(language.text("恭喜完成！", "Puzzle Complete!"))
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Color.puzzleIvory)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier("completionTitle")
            Text(language.text("\(language.difficultyTitle(result.difficulty)) · \(result.pieceCount) 块拼图", "\(language.difficultyTitle(result.difficulty)) · \(result.pieceCount) pieces"))
                .font(.subheadline)
                .foregroundStyle(Color.puzzleMuted)

            VStack(spacing: 7) {
                Text(language.text("本次用时", "YOUR TIME"))
                    .font(.caption.monospaced()).foregroundStyle(Color.puzzleMuted)
                Text(result.durationText(language: language))
                    .font(.system(size: 29, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.puzzleBrass)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityIdentifier("completionTime")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.puzzleIvory.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(encouragement)
                .font(.subheadline)
                .foregroundStyle(Color.puzzleIvory)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button(action: onViewPuzzle) {
                    Text(language.text("欣赏作品", "Enjoy Your Puzzle")).frame(maxWidth: .infinity)
                }
                .buttonStyle(BrassButtonStyle())
                .accessibilityIdentifier("completionViewPuzzle")
                Button(action: onPlayAgain) {
                    Label(language.text("再来一局", "Play Again"), systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.puzzleIvory)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("completionPlayAgain")
            }
        }
        .padding(26)
        .background {
            WoodTexture(tone: .walnut)
                .overlay(Color.puzzleCharcoal.opacity(0.8))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.puzzleBrass.opacity(0.5), lineWidth: 1) }
        .shadow(color: .black.opacity(0.4), radius: 25, y: 12)
        .scaleEffect(revealed || reduceMotion ? 1 : 0.92)
        .opacity(revealed ? 1 : 0)
    }

    private var encouragement: String {
        switch result.difficulty {
        case .easy:
            return language.text("每一块耐心，都拼成了这一刻。下一幅也一定精彩！", "Piece by piece, your patience brought it all together. On to the next memory!")
        case .normal:
            return language.text("你把细节拼成了完整，让耐心有了漂亮的答案。", "You turned all those little details into something whole. Your patience paid off!")
        case .hard, .nightmare, .hell:
            return language.text("这么多碎片也难不倒你，专注和坚持都值得喝彩！", "So many pieces, and you kept going. Your focus and persistence deserve a celebration!")
        }
    }
}

/// Core Animation 彩纸粒子，不使用逐帧 SwiftUI 状态更新。
private struct CompletionConfetti: UIViewRepresentable {
    func makeUIView(context: Context) -> CompletionConfettiCanvas { CompletionConfettiCanvas() }
    func updateUIView(_ uiView: CompletionConfettiCanvas, context: Context) {}
    static func dismantleUIView(_ uiView: CompletionConfettiCanvas, coordinator: ()) { uiView.stop() }
}

private final class CompletionConfettiCanvas: UIView {
    private var emitter: CAEmitterLayer?
    private var stopEmission: DispatchWorkItem?
    private var removeParticles: DispatchWorkItem?
    private var started = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if !started { start() }
        emitter?.emitterPosition = CGPoint(x: bounds.midX, y: -12)
        emitter?.emitterSize = CGSize(width: bounds.width, height: 1)
    }

    private func start() {
        started = true
        let emitter = CAEmitterLayer()
        emitter.beginTime = CACurrentMediaTime()
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        let colors = [UIColor(red: 0.85, green: 0.68, blue: 0.35, alpha: 1),
                      UIColor(red: 0.94, green: 0.91, blue: 0.84, alpha: 1),
                      UIColor(red: 0.67, green: 0.34, blue: 0.24, alpha: 1),
                      UIColor(red: 0.42, green: 0.60, blue: 0.48, alpha: 1)]
        emitter.emitterCells = colors.enumerated().map { index, color in
            let cell = CAEmitterCell()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            cell.contents = UIGraphicsImageRenderer(size: CGSize(width: 7, height: 11), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 7, height: 11))
            }.cgImage
            cell.birthRate = 18
            cell.lifetime = 3.4
            cell.velocity = 110
            cell.velocityRange = 45
            cell.yAcceleration = 110
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 3
            cell.spin = index.isMultiple(of: 2) ? 2 : -2
            cell.spinRange = 3
            cell.scaleRange = 0.3
            cell.alphaSpeed = -0.18
            return cell
        }
        layer.addSublayer(emitter)
        self.emitter = emitter
        let stop = DispatchWorkItem { [weak emitter] in emitter?.birthRate = 0 }
        let remove = DispatchWorkItem { [weak self] in self?.stop() }
        stopEmission = stop
        removeParticles = remove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: stop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2, execute: remove)
    }

    func stop() {
        stopEmission?.cancel()
        removeParticles?.cancel()
        stopEmission = nil
        removeParticles = nil
        emitter?.removeFromSuperlayer()
        emitter = nil
    }
}
