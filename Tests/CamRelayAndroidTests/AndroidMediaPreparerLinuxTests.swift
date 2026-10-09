#if os(Linux)
@testable import CamRelayAndroid
import CamRelayCore
import Foundation
import Testing

@Test("Linux media preparation fits pixels, caches results, and removes temporary media")
func preparesLinuxImage() throws {
    let root = try linuxFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("red.png")
    _ = try mediaTool("ffmpeg", [
        "-f", "lavfi", "-i", "color=red:size=160x120", "-frames:v", "1", source.path,
    ])
    let preparer = try AndroidMediaPreparer()
    let media = try MediaFixture(path: source.path)
    let prepared = try preparer.prepare(media)
    #expect(prepared.url != source)
    #expect(try preparer.prepare(media) == prepared)
    let center = try linuxPixel(prepared.url, x: 20, y: 60)
    #expect(center[0] > 240 && center[1] < 20 && center[2] < 20)
    #expect(try linuxPixel(prepared.url, x: 150, y: 60) == [0, 0, 0])
    #expect(try linuxPixel(prepared.url, x: 20, y: 30) == [0, 0, 0])
    _ = try mediaTool("ffmpeg", [
        "-y", "-f", "lavfi", "-i", "color=blue:size=240x180", "-frames:v", "1", source.path,
    ])
    let refreshed = try preparer.prepare(media)
    #expect(refreshed.url != prepared.url)
    let blue = try linuxPixel(refreshed.url, x: 30, y: 90)
    #expect(blue[0] < 20 && blue[1] < 20 && blue[2] > 240)
    preparer.cleanup()
    #expect(!FileManager.default.fileExists(atPath: prepared.url.path))
    #expect(!FileManager.default.fileExists(atPath: refreshed.url.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test("Linux portrait preparation preserves all four image quadrants")
func preparesLinuxPortraitImage() throws {
    let root = try linuxFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("quadrants.ppm")
    let source = root.appendingPathComponent("portrait.png")
    try writeLinuxQuadrants(to: original, width: 120, height: 240)
    _ = try mediaTool("ffmpeg", ["-i", original.path, source.path])
    let preparer = try AndroidMediaPreparer()
    let prepared = try preparer.prepare(MediaFixture(path: source.path))
    let red = try linuxPixel(prepared.url, x: 21, y: 86)
    let green = try linuxPixel(prepared.url, x: 43, y: 86)
    let blue = try linuxPixel(prepared.url, x: 21, y: 152)
    let yellow = try linuxPixel(prepared.url, x: 43, y: 152)
    #expect(red[0] > 240 && red[1] < 20 && red[2] < 20)
    #expect(green[0] < 20 && green[1] > 240 && green[2] < 20)
    #expect(blue[0] < 20 && blue[1] < 20 && blue[2] > 240)
    #expect(yellow[0] > 240 && yellow[1] > 240 && yellow[2] < 20)
    #expect(try linuxPixel(prepared.url, x: 5, y: 120) == [0, 0, 0])
    #expect(try linuxPixel(prepared.url, x: 60, y: 120) == [0, 0, 0])
}

@Test("Linux video preparation applies rotation and preserves cadence and duration")
func preparesLinuxRotatedVideo() throws {
    let root = try linuxFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original.mp4")
    let source = root.appendingPathComponent("rotated.mp4")
    let quadrants = root.appendingPathComponent("quadrants.ppm")
    try writeLinuxQuadrants(to: quadrants, width: 160, height: 120)
    _ = try mediaTool("ffmpeg", [
        "-loop", "1", "-framerate", "12", "-i", quadrants.path, "-t", "1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", original.path,
    ])
    _ = try mediaTool("ffmpeg", [
        "-display_rotation", "-90", "-i", original.path, "-c", "copy", source.path,
    ])
    let preparer = try AndroidMediaPreparer()
    let prepared = try preparer.prepare(MediaFixture(path: source.path))
    let data = try mediaTool("ffprobe", [
        "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate,duration,nb_frames:stream_side_data=rotation",
        "-of", "json", prepared.url.path,
    ])
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let streams = try #require(json["streams"] as? [[String: Any]])
    let stream = try #require(streams.first)
    #expect(stream["width"] as? Int == 120)
    #expect(stream["height"] as? Int == 160)
    #expect(stream["r_frame_rate"] as? String == "12/1")
    #expect(stream["duration"] as? String == "1.000000")
    #expect(stream["nb_frames"] as? String == "12")
    let sideData = stream["side_data_list"] as? [[String: Any]] ?? []
    #expect(sideData.allSatisfy { ($0["rotation"] as? Int ?? 0) == 0 })
    // A -90-degree display rotation moves the original bottom-left blue quadrant to the top-left.
    let blue = try linuxPixel(prepared.url, x: 16, y: 56)
    let red = try linuxPixel(prepared.url, x: 49, y: 56)
    let yellow = try linuxPixel(prepared.url, x: 16, y: 102)
    let green = try linuxPixel(prepared.url, x: 49, y: 102)
    #expect(blue[0] < 30 && blue[1] < 30 && blue[2] > 220)
    #expect(red[0] > 220 && red[1] < 30 && red[2] < 30)
    #expect(yellow[0] > 220 && yellow[1] > 220 && yellow[2] < 30)
    #expect(green[0] < 30 && green[1] > 220 && green[2] < 30)
}

@Test("Linux failed preparation preserves previously prepared media")
func preservesLinuxMediaAfterFailure() throws {
    let root = try linuxFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("red.png")
    let invalid = root.appendingPathComponent("invalid.mp4")
    _ = try mediaTool("ffmpeg", [
        "-f", "lavfi", "-i", "color=red:size=160x120", "-frames:v", "1", source.path,
    ])
    try Data("unsupported media".utf8).write(to: invalid)
    let preparer = try AndroidMediaPreparer()
    let media = try MediaFixture(path: source.path)
    let prepared = try preparer.prepare(media)
    #expect(throws: RelayError.self) { try preparer.prepare(MediaFixture(path: invalid.path)) }
    #expect(try preparer.prepare(media) == prepared)
    #expect(FileManager.default.fileExists(atPath: prepared.url.path))
}

private func linuxFixtureDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("camrelay-linux-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

private func writeLinuxQuadrants(to url: URL, width: Int, height: Int) throws {
    let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
    var pixels = Data("P6\n\(width) \(height)\n255\n".utf8)
    for y in 0..<height {
        for x in 0..<width {
            pixels.append(contentsOf: colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)])
        }
    }
    try pixels.write(to: url)
}

private func linuxPixel(_ source: URL, x: Int, y: Int) throws -> [UInt8] {
    let data = try mediaTool("ffmpeg", [
        "-i", source.path, "-vf", "format=rgb24,crop=1:1:\(x):\(y)", "-frames:v", "1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
    ])
    #expect(data.count == 3)
    return Array(data)
}

private func mediaTool(_ name: String, _ arguments: [String]) throws -> Data {
    try runLinuxAndroidCommand(
        URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [name, "-v", "error"] + arguments,
        environment: ProcessInfo.processInfo.environment
    )
}
#endif
