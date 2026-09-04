import CamRelayCore
import Foundation
import Testing

@Test("Recognizes supported image and video extensions")
func recognizesSupportedExtensions() {
    #expect(MediaFixture.kind(forExtension: "PNG") == .image)
    #expect(MediaFixture.kind(forExtension: "jpeg") == .image)
    #expect(MediaFixture.kind(forExtension: "mp4") == .video)
    #expect(MediaFixture.kind(forExtension: "MOV") == .video)
    #expect(MediaFixture.kind(forExtension: "txt") == nil)
}

@Test("Rejects a missing fixture")
func rejectsMissingFixture() {
    #expect(throws: MediaFixtureError.fileNotFound("missing.mp4")) {
        _ = try MediaFixture(path: "missing.mp4")
    }
}
