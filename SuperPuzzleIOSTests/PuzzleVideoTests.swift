import AVFoundation
import XCTest
import UIKit
@testable import SuperPuzzle

/// 使用本地生成的视频验证真实解码、拖动定位和播放生命周期。
@MainActor
final class PuzzleVideoTests: XCTestCase {
    private func makeVideo(portrait: Bool = false) async throws -> URL {
        let importRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SuperPuzzleImports", isDirectory: true)
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        let directory = importRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128, AVVideoHeightKey: 64
        ])
        if portrait { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<40 {
            try await waitUntil { input.isReadyForMoreMediaData || writer.status == .failed }
            var pixelBuffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixelBuffer), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 128, height: 64,
                                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(index < 20 ? UIColor.red.cgColor : UIColor.blue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 20)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func waitUntil(timeout: Double = 8, _ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), "等待视频状态超时")
    }

    private func isBlue(_ image: CGImage?) -> Bool {
        guard let image else { return false }
        var pixel: [UInt8] = [0, 0, 0, 0]
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel[2] > 180 && pixel[0] < 80
    }

    func testPortraitVideoPreservesOrientation() async throws {
        let url = try await makeVideo(portrait: true)
        defer { PuzzleVideoController.removeImportedFile(at: url) }
        let source = try await PuzzleVideoSource.prepare(url: url)
        XCTAssertEqual(source.poster.width, 64)
        XCTAssertEqual(source.poster.height, 128)
        XCTAssertEqual(source.duration, 2, accuracy: 0.1)
    }

    func testPausedSeekUpdatesDecodedFrameAndLastSeekWins() async throws {
        let source = try await PuzzleVideoSource.prepare(url: makeVideo())
        let video = PuzzleVideoController()
        defer { video.reset() }
        video.configure(source)
        try await waitUntil { video.isReady }
        video.seek(to: 0.2)
        video.seek(to: 0.7)
        video.seek(to: 1.4)
        try await waitUntil { abs(video.currentTime - 1.4) < 0.12 && self.isBlue(video.frame) }
        XCTAssertFalse(video.isPlaying)
        video.seek(to: -100)
        try await waitUntil { video.currentTime < 0.1 }
        video.seek(to: .nan)
        XCTAssertTrue(video.currentTime.isFinite)
    }

    func testPlaybackScrubbingMuteAndReset() async throws {
        let source = try await PuzzleVideoSource.prepare(url: makeVideo())
        let video = PuzzleVideoController()
        defer { video.reset() }
        video.configure(source)
        try await waitUntil { video.isReady }
        XCTAssertTrue(video.isMuted)
        video.toggleMute()
        XCTAssertFalse(video.isMuted)
        video.play()
        try await waitUntil { video.currentTime > 0.2 }
        video.beginScrubbing()
        XCTAssertFalse(video.isPlaying)
        video.endScrubbing(at: 1.2)
        try await waitUntil { video.isPlaying && video.currentTime >= 1.1 }
        video.pause()
        let stoppedTime = video.currentTime
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(video.currentTime, stoppedTime, accuracy: 0.15)
        video.beginScrubbing()
        video.endScrubbing(at: 0.4)
        try await waitUntil { abs(video.currentTime - 0.4) < 0.12 }
        XCTAssertFalse(video.isPlaying)
        video.reset()
        XCTAssertFalse(video.hasVideo)
        XCTAssertNil(video.frame)
        XCTAssertEqual(video.duration, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.url.path))
    }

    func testPlayingVideoLoops() async throws {
        let source = try await PuzzleVideoSource.prepare(url: makeVideo())
        let video = PuzzleVideoController()
        defer { video.reset() }
        video.configure(source)
        try await waitUntil { video.isReady }
        video.seek(to: 1.7)
        try await waitUntil { video.currentTime > 1.6 }
        video.play()
        try await waitUntil { video.currentTime < 0.8 }
        XCTAssertTrue(video.isPlaying)
    }

    func testVideoPuzzleSharesImageAndHintNeverMovesPieces() async throws {
        let source = try await PuzzleVideoSource.prepare(url: makeVideo())
        defer { PuzzleVideoController.removeImportedFile(at: source.url) }
        let model = PuzzleViewModel()
        defer { model.stopTimer() }
        model.start(with: UIImage(cgImage: source.poster), usesVideo: true)
        let before = model.pieces.map(\.id)
        let image = try XCTUnwrap(model.pieces.first?.image)
        XCTAssertTrue(model.pieces.allSatisfy { $0.image === image })
        model.showHint()
        XCTAssertEqual(model.pieces.map(\.id), before)
        let hint = try XCTUnwrap(model.hint)
        model.swap(from: hint.source, to: hint.destination)
        XCTAssertEqual(model.pieces[hint.destination].id, hint.destination)
        XCTAssertNil(model.hint)
    }

    func testCanvasDrawsSharedFrameAtEachPiecesOriginalPosition() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 90), format: format)
        let colors: [UIColor] = [.red, .green, .blue, .yellow, .cyan, .magenta, .orange, .purple, .brown]
        let mosaic = renderer.image { context in
            for index in colors.indices {
                colors[index].setFill()
                context.fill(CGRect(x: (index % 3) * 30, y: (index / 3) * 30, width: 30, height: 30))
            }
        }
        let video = PuzzleVideoController()
        defer { video.reset() }
        let canvas = VideoBoardCanvas(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
        canvas.contentScaleFactor = 1
        canvas.connect(video)
        let order = [8, 0, 1, 2, 3, 4, 5, 6, 7]
        let edges = PuzzleEdges(top: .flat, right: .flat, bottom: .flat, left: .flat)
        let pieces = order.map { PuzzlePiece(id: $0, image: mosaic, edges: edges) }
        canvas.configure(pieces: pieces, rows: 3, columns: 3, draggedIndex: nil,
                         translation: .zero, selectedIndex: nil, hintedIndices: [])
        canvas.layoutIfNeeded()
        video.frames.send(try XCTUnwrap(mosaic.cgImage))
        try await waitUntil { canvas.renderedFrame != nil }
        let drawn = try XCTUnwrap(canvas.renderedFrame)
        let source = try XCTUnwrap(mosaic.cgImage)
        for (position, original) in order.enumerated() {
            XCTAssertEqual(sample(drawn, at: position), sample(source, at: original))
        }
        // 位置变换或父页面刷新带来相同配置时，不再重复合成暂停的画面。
        canvas.configure(pieces: pieces, rows: 3, columns: 3, draggedIndex: nil,
                         translation: .zero, selectedIndex: nil, hintedIndices: [])
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(canvas.renderedFrame === drawn)
        // 切换共享帧后，每个碎片都必须更新，而不是停留在封面。
        let next = renderer.image { context in
            UIColor.cyan.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 90, height: 90))
        }
        video.frames.send(try XCTUnwrap(next.cgImage))
        try await waitUntil { canvas.renderedFrame !== drawn }
        let updated = try XCTUnwrap(canvas.renderedFrame)
        for position in order.indices {
            XCTAssertEqual(sample(updated, at: position), sample(try XCTUnwrap(next.cgImage), at: position))
        }
    }

    private func sample(_ image: CGImage, at index: Int) -> [UInt8] {
        let crop = image.cropping(to: CGRect(x: (index % 3) * 30 + 15, y: (index / 3) * 30 + 15, width: 1, height: 1))!
        var pixel: [UInt8] = [0, 0, 0, 0]
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }

    func testUnreadableVideoReportsError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data("invalid video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await PuzzleVideoSource.prepare(url: url)
            XCTFail("损坏的视频应当导入失败")
        } catch { /* Expected. */ }
    }
}
