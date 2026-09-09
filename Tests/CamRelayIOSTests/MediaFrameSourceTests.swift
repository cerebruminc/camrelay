import CoreGraphics
import Testing
@testable import CamRelayIOS

@Suite("Media frame source")
struct MediaFrameSourceTests {
    @Test("identity video metadata keeps the encoded dimensions")
    func identityDisplayGeometry() throws {
        let geometry = try VideoDisplayGeometry(
            naturalSize: CGSize(width: 640, height: 360),
            preferredTransform: .identity
        )

        #expect(geometry.width == 640)
        #expect(geometry.height == 360)
        #expect(geometry.transform == .identity)
    }

    @Test("rotation metadata produces upright portrait pixels")
    func rotatedDisplayGeometry() throws {
        let geometry = try VideoDisplayGeometry(
            naturalSize: CGSize(width: 640, height: 360),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        let outputBounds = CGRect(x: 0, y: 0, width: 640, height: 360)
            .applying(geometry.transform)
            .standardized

        #expect(geometry.width == 360)
        #expect(geometry.height == 640)
        #expect(abs(outputBounds.minX) < 0.001)
        #expect(abs(outputBounds.minY) < 0.001)
        #expect(abs(outputBounds.width - 360) < 0.001)
        #expect(abs(outputBounds.height - 640) < 0.001)
    }
}
