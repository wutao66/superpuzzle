import SwiftUI

/// 木纹背景的明暗类型。
enum WoodTone {
    case walnut
    case oak
}

/// 显示可覆盖任意尺寸的木质纹理背景。
struct WoodTexture: View {
    /// 木纹使用的明暗类型。
    let tone: WoodTone

    /// 构建木纹图片及用于提升文字可读性的遮罩。
    var body: some View {
        Image(tone == .walnut ? "WalnutTexture" : "OakTexture")
            .resizable()
            .scaledToFill()
            .overlay(tone == .walnut ? Color.black.opacity(0.34) : Color.black.opacity(0.08))
            .clipped()
            .allowsHitTesting(false)
    }
}

/// Super Puzzle 使用的材质配色。
extension Color {
    /// 温暖的象牙白主文字颜色。
    static let puzzleIvory = Color(red: 0.94, green: 0.91, blue: 0.84)
    /// 低饱和黄铜强调色。
    static let puzzleBrass = Color(red: 0.73, green: 0.57, blue: 0.27)
    /// 深色控件背景颜色。
    static let puzzleCharcoal = Color(red: 0.10, green: 0.095, blue: 0.085)
    /// 辅助信息使用的暖灰颜色。
    static let puzzleMuted = Color(red: 0.68, green: 0.64, blue: 0.56)
}

/// 黄铜质感的主要操作按钮样式。
struct BrassButtonStyle: ButtonStyle {
    /// 根据按钮交互状态构建样式。
    /// - Parameter configuration: SwiftUI 提供的按钮状态。
    /// - Returns: 带黄铜底色和按压反馈的按钮视图。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.puzzleCharcoal)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(Color.puzzleBrass.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
