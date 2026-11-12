// What: Tests the extended FaceAdjustments: new slider boundaries, clamp,
// Codable round-trip, and backward-compatible decode of old state.json.
// Inputs/Outputs: Slider values / JSON in; amounts / decoded state out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class FaceAdjustmentsTests: XCTestCase {

    func testNewSliderBoundaries() {
        XCTAssertEqual(mappedAmount(slider: 100, tool: .eyeHeight), 0.20, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -100, tool: .eyeHeight), -0.20, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 0, tool: .eyeHeight), 0, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .eyeWidth), 0.20, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .eyeLength), 0.10, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .eyePuffy), 0.15, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -100, tool: .eyeAngle), -0.08, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .eyePosition), 0.08, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .noseLift), 0.12, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .noseAla), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -100, tool: .noseAla), -0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .noseRoot), 0.15, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .noseBridge), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .noseTip), 0.15, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .lipWidth), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .lipSmile), 0.12, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .lipPosition), 0.10, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .lipMShape), 0.15, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .browHeight), 0.10, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .browDistance), 0.08, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .browAngle), 0.08, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .browLength), 0.10, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .browShape), 0.15, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .chinWidth), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -100, tool: .chinWidth), -0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .cheekbones), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .temples), 0.20, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .foreheadHeight), 0.15, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .faceLength), 0.20, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .vShape), 0.25, accuracy: 0.0001)
    }

    func testNewSliderClamp() {
        XCTAssertEqual(mappedAmount(slider: 250, tool: .noseAla), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -250, tool: .vShape), -0.25, accuracy: 0.0001)
    }

    func testSkinGrainBoundaries() {
        XCTAssertEqual(mappedAmount(slider: 100, tool: .skinGrain), 1.0, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 0, tool: .skinGrain), 0, accuracy: 0.0001)
        // One-way tool: negative sliders clamp to zero, never negative.
        XCTAssertEqual(mappedAmount(slider: -100, tool: .skinGrain), 0, accuracy: 0.0001)
    }

    func testAllWarpToolsAreMapped() {
        for tool in allWarpTools {
            XCTAssertGreaterThan(toolMapping(for: tool).maxAmount, 0, "\(tool)")
            XCTAssertGreaterThan(toolMapping(for: tool).radiusInIPD, 0, "\(tool)")
        }
    }

    func testCodableRoundTrip() throws {
        var face = FaceAdjustments()
        face.eyeHeight = 40
        face.noseAla = -30
        face.lipMShape = 25
        face.chinWidth = -15
        face.vShape = 60
        face.yawAttenuation = 0.5
        let data = try JSONEncoder().encode(face)
        let decoded = try JSONDecoder().decode(FaceAdjustments.self, from: data)
        XCTAssertEqual(decoded, face)
    }

    func testOldJSONDecodesWithZeroDefaults() throws {
        // state.json written before the 32-slider extension: only the
        // original 10 face fields. New fields must decode as 0, not fail.
        let json = """
        {"faceId":"face-0","eyeSize":20,"eyeSpacing":-10,"noseSize":0,
        "noseWidth":15,"lipSize":0,"lipThickness":5,"browThickness":0,
        "faceWidth":-20,"jawSize":10,"chinLength":0,"scope":"general"}
        """.data(using: .utf8) ?? Data()
        let decoded = try JSONDecoder().decode(FaceAdjustments.self, from: json)
        XCTAssertEqual(decoded.eyeSize, 20, accuracy: 0.0001)
        XCTAssertEqual(decoded.noseWidth, 15, accuracy: 0.0001)
        XCTAssertEqual(decoded.eyeHeight, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.noseAla, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.lipMShape, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.chinWidth, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.vShape, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.yawAttenuation, 0, accuracy: 0.0001)
    }

    func testOldSkinJSONDecodesGrainAsZero() throws {
        let json = """
        {"smoothing":30,"texture":70,"shine":0,"wrinkle":0,"acne":0,
        "darkCircles":0,"teethWhitening":0,"eyeEnhance":0}
        """.data(using: .utf8) ?? Data()
        let decoded = try JSONDecoder().decode(SkinAdjustments.self, from: json)
        XCTAssertEqual(decoded.smoothing, 30, accuracy: 0.0001)
        XCTAssertEqual(decoded.texture, 70, accuracy: 0.0001)
        XCTAssertEqual(decoded.grain, 0, accuracy: 0.0001)
    }

    func testTextureKeepSemantics() {
        // DECISION (see DEBUG_LOG.md): skin.texture means texture KEPT.
        // 100 = full detail preserved, 0 = fully smoothed low pass.
        // textureKeep01 = texture / 100; a keep of 1 returns the source
        // exactly through the CPU skin-blend reference.
        let src: [Float] = [0.2, 0.8, 0.5]
        let low: [Float] = [0.4, 0.6, 0.5]
        let mask: [Float] = [1, 1, 1]
        let kept = skinSmoothBlendCPU(src: src, low: low, skinMask: mask, strength: 1, textureKeep: 1)
        XCTAssertEqual(kept, src)
        let removed = skinSmoothBlendCPU(src: src, low: low, skinMask: mask, strength: 1, textureKeep: 0)
        XCTAssertEqual(removed, low)
    }
}
