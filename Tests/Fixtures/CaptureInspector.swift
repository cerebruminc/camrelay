import AVFoundation
import Foundation
import ImageIO

/// Validates saved captures independently of the app that produced them.
@main
struct CaptureInspector {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("capture-inspector: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        guard CommandLine.arguments.count > 1 else { throw Failure("Provide captured image or movie paths.") }
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--compare" {
            let reference = try await firstImage(URL(fileURLWithPath: CommandLine.arguments[2]))
            let capture = try await firstImage(URL(fileURLWithPath: CommandLine.arguments[3]))
            let expected = try pixels(reference, width: capture.width, height: capture.height)
            let actual = try pixels(capture, width: capture.width, height: capture.height)
            let difference = zip(expected, actual).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            let meanError = Double(difference) / Double(expected.count)
            guard meanError < 12 else { throw Failure("Capture does not match fixture: mean channel error \(meanError)") }
            print("capture matches fixture: mean channel error \(meanError)")
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fixtures" {
            try await validateFixtures(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
            return
        }
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            if ["mov", "mp4"].contains(url.pathExtension.lowercased()) {
                try await inspectMovie(url)
            } else {
                try inspectImage(url)
            }
        }
    }

    static func firstImage(_ url: URL, at seconds: Double = 0) async throws -> CGImage {
        if ["mov", "mp4"].contains(url.pathExtension.lowercased()) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure("Cannot decode image: \(url.path)")
        }
        return image
    }

    /// Fits the whole image into a black frame, matching the session's geometry.
    static func pixels(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height * 4)
        try result.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw Failure("Cannot create comparison bitmap.")
            }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
            let fittedWidth = Double(image.width) * scale
            let fittedHeight = Double(image.height) * scale
            context.draw(image, in: CGRect(x: (Double(width) - fittedWidth) / 2,
                y: (Double(height) - fittedHeight) / 2, width: fittedWidth, height: fittedHeight))
        }
        return result
    }

    static func validateFixtures(_ directory: URL) async throws {
        let pattern = try await firstImage(directory.appendingPathComponent("checkerboard.png"))
        guard pattern.width == 480, pattern.height == 640 else { throw Failure("Unexpected checkerboard dimensions.") }
        let grid = try pixels(pattern, width: 480, height: 640)
        // Every tile is monochrome, and neighboring tiles alternate in both axes.
        for y in 0..<8 {
            for x in 0..<6 {
                let offset = ((y * 80 + 40) * 480 + x * 80 + 40) * 4
                let value = grid[offset]
                guard (value < 5 || value > 250), grid[offset + 1] == value, grid[offset + 2] == value,
                      (x == 0 || grid[offset - 80 * 4] != value),
                      (y == 0 || grid[offset - 80 * 480 * 4] != value) else { throw Failure("Invalid checkerboard tile.") }
            }
        }
        for (name, width, height, fps) in [("colors.mp4", 320, 240, Float(15)), ("moving-shapes.mp4", 1280, 720, Float(24))] {
            let url = directory.appendingPathComponent(name)
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first,
                  try await track.load(.nominalFrameRate) == fps,
                  abs(try await asset.load(.duration).seconds - 3) < 0.01 else { throw Failure("Unexpected video timing: \(name)") }
            var samples: [[UInt8]] = []
            for second in [0.0, 0.5, 1.0, 2.0] {
                let image = try await firstImage(url, at: second)
                guard image.width == width, image.height == height else { throw Failure("Unexpected dimensions: \(name)") }
                samples.append(try pixels(image, width: 64, height: 48))
            }
            if name == "moving-shapes.mp4" {
                guard Set(samples).count == 4 else { throw Failure("Shapes are not moving.") }
                let first = samples[0]
                var red = 0, green = 0
                for index in stride(from: 0, to: first.count, by: 4) {
                    if first[index] > 180 && first[index + 1] < 120 { red += 1 }
                    if first[index + 1] > 180 && first[index] < 120 { green += 1 }
                }
                guard red > 30, green > 30 else { throw Failure("Missing colored shapes.") }
            } else {
                for (index, channel) in [(0, 0), (2, 1), (3, 2)] {
                    let center = (24 * 64 + 32) * 4
                    let rgb = (0..<3).map { Int(samples[index][center + $0]) }
                    guard rgb[channel] > 180, (0..<3).filter({ $0 != channel }).allSatisfy({ rgb[channel] > rgb[$0] + 100 }) else {
                        throw Failure("Wrong color sequence: sample \(index), RGB \(rgb)")
                    }
                }
            }
            try await inspectMovie(url)
        }
        print("PASS: checkerboard tiles, video dimensions/rates/duration, colors, motion, and decoded timestamps")
    }

    static func inspectImage(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure("Cannot decode image: \(url.path)")
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw Failure("Cannot sample image pixels.") }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        print("image \(url.lastPathComponent) \(image.width)x\(image.height) rgb=\(pixel[0]),\(pixel[1]),\(pixel[2])")
    }

    static func inspectMovie(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure("Movie is not playable: \(url.path)")
        }
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure("Cannot read movie.") }
        var count = 0
        var previous = -Double.infinity
        var colors: Set<String> = []
        var transitions = 0
        var previousColor: String?
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time > previous, let pixels = CMSampleBufferGetImageBuffer(sample) else {
                throw Failure("Invalid movie frame or non-increasing timestamp.")
            }
            previous = time
            count += 1
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                let center = base.advanced(by: CVPixelBufferGetHeight(pixels) / 2 * CVPixelBufferGetBytesPerRow(pixels)
                    + CVPixelBufferGetWidth(pixels) / 2 * 4).assumingMemoryBound(to: UInt8.self)
                let channels = [Int(center[2]), Int(center[1]), Int(center[0])]
                let labels = ["red", "green", "blue"]
                if let index = channels.indices.max(by: { channels[$0] < channels[$1] }), channels[index] > 80 {
                    let color = labels[index]
                    colors.insert(color)
                    if let previousColor, previousColor != color { transitions += 1 }
                    previousColor = color
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        }
        guard reader.status == .completed, count > 0, duration > 0 else {
            throw reader.error ?? Failure("Movie has no complete frames.")
        }
        print("movie \(url.lastPathComponent) duration=\(duration) frames=\(count) colors=\(colors.sorted()) transitions=\(transitions)")
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
