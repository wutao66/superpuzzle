import SwiftUI

/// Super Puzzle 应用入口。
@main
struct SuperPuzzleApp: App {
    /// 创建应用的根视图。
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

/// 在系统启动画面和主界面之间提供连贯的品牌过渡。
private struct AppRootView: View {
    /// 是否仍显示应用内启动页。
    @State private var isShowingLaunch = true
    /// 用户选择的界面语言；未选择时跟随手机系统语言。
    @AppStorage("app.language") private var languageCode = AppLanguage.systemDefault.rawValue

    /// 当前有效语言。
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .english }

    /// 构建主界面与启动页叠层。
    var body: some View {
        ZStack {
            ContentView()

            if isShowingLaunch {
                LaunchView(language: language)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(\.locale, language.locale)
        .task {
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                isShowingLaunch = false
            }
        }
    }
}

/// 展示 Super Puzzle 品牌标志的应用内启动页。
private struct LaunchView: View {
    /// 启动页使用的显示语言。
    let language: AppLanguage
    /// 是否已经开始标志入场动画。
    @State private var isRevealed = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 构建启动页内容。
    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .scaleEffect(isRevealed || reduceMotion ? 1 : 0.86)
                    .opacity(isRevealed || reduceMotion ? 1 : 0)

                Text("SUPER PUZZLE")
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.puzzleIvory)
                    .padding(.top, 22)

                Rectangle()
                    .fill(Color.puzzleBrass)
                    .frame(width: 34, height: 2)
                    .padding(.top, 15)

                Text(language.text("把记忆拼回来", "PIECE THE MEMORY BACK"))
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.puzzleMuted)
                    .padding(.top, 13)
            }
            .offset(y: -18)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                isRevealed = true
            }
        }
    }
}
