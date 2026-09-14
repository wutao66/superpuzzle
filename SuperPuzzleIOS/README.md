# Super Puzzle iOS

这是 SwiftUI 原生实现。使用 Xcode 新建一个 iOS App（SwiftUI、Swift），将本目录下的 `SuperPuzzleApp.swift`、`ContentView.swift`、`PuzzleModel.swift` 加入 target 即可运行。

最低系统版本建议设为 iOS 16，以使用 `PhotosPicker`。不需要额外依赖或相册权限弹窗；图片只在本地内存中切片。

## 规则

- 简单：9 片
- 普通：100 片
- 困难：300 片
- 噩梦：1000 片
- 地狱：2000 片

行列数会从目标片数的因数中按原图宽高比择优，因此拼图块不是强制正方形。棋盘中点击两块即可交换位置，完成后自动停止计时。
