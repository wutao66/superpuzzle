import Combine
import UIKit
import XCTest
@testable import SuperPuzzle

@MainActor
final class PuzzleCompletionTests: XCTestCase {
    func testCompletionTimeFormatsSecondsMinutesAndHours() {
        let cases: [(Int, String, String)] = [
            (0, "0秒", "0s"), (59, "59秒", "59s"), (60, "1分 0秒", "1m 0s"),
            (3599, "59分 59秒", "59m 59s"), (3661, "1小时 1分 1秒", "1h 1m 1s")
        ]
        for (seconds, chinese, english) in cases {
            let result = PuzzleCompletionResult(elapsedSeconds: seconds, pieceCount: 9, difficulty: .easy)
            XCTAssertEqual(result.durationText(language: .chinese), chinese)
            XCTAssertEqual(result.durationText(language: .english), english)
        }
    }

    func testCompletionOccursOncePerGameAndTimeStops() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 90)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 90, height: 90))
        }
        let model = PuzzleViewModel()
        defer { model.stopTimer() }
        var completions = 0
        let subscription = model.$isComplete.dropFirst().filter { $0 }.sink { _ in completions += 1 }
        defer { subscription.cancel() }
        model.start(with: image)
        solve(model)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(completions, 1)
        let result = PuzzleCompletionResult(elapsedSeconds: model.elapsedSeconds, pieceCount: model.pieces.count,
                                            difficulty: model.difficulty)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(model.elapsedSeconds, result.elapsedSeconds)
        model.tap(index: 0)
        model.swap(from: 0, to: 1)
        XCTAssertEqual(completions, 1)

        model.start(with: image)
        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.elapsedSeconds, 0)
        solve(model)
        XCTAssertEqual(completions, 2)
        XCTAssertEqual(result.pieceCount, 9)
    }

    private func solve(_ model: PuzzleViewModel) {
        // 每次建议交换至少让一块归位，至多需要片数减一次。
        for _ in model.pieces.indices where !model.isComplete {
            model.showHint()
            guard let hint = model.hint else { XCTFail("错位棋盘应有交换建议"); return }
            model.swap(from: hint.source, to: hint.destination)
        }
    }
}
