// What: Tests the canonical color-grade math (resolve + per-pixel grade
// + crop rect). The Metal colorGrade kernel must mirror gradePixel()
// exactly, so these tests pin the shared behavior.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class ColorGradeTests: XCTestCase {

    private func neutral() -> ResolvedColorGrade {
        resolveColorGrade(exposure: 0, contrast: 0, saturation: 0, warmth: 0, preset: .none, intensity: 0)
    }

    func testNeutralGradeIsIdentity() {
        let grade = neutral()
        XCTAssertEqual(grade.exposureEV, 0, accuracy: 0.0001)
        XCTAssertEqual(grade.contrastFactor, 1, accuracy: 0.0001)
        XCTAssertEqual(grade.saturationFactor, 1, accuracy: 0.0001)
        XCTAssertEqual(grade.warmth, 0, accuracy: 0.0001)
        let out = gradePixel(r: 0.2, g: 0.5, b: 0.8, grade: grade)
        XCTAssertEqual(out.r, 0.2, accuracy: 0.0001)
        XCTAssertEqual(out.g, 0.5, accuracy: 0.0001)
        XCTAssertEqual(out.b, 0.8, accuracy: 0.0001)
    }

    func testExposurePlus100Doubles() {
        // +100 exposure = +2 EV = 4x; a 0.2 input becomes 0.8.
        let grade = resolveColorGrade(exposure: 100, contrast: 0, saturation: 0, warmth: 0, preset: .none, intensity: 0)
        XCTAssertEqual(grade.exposureEV, 2, accuracy: 0.0001)
        let out = gradePixel(r: 0.2, g: 0.2, b: 0.2, grade: grade)
        XCTAssertEqual(out.r, 0.8, accuracy: 0.0001)
    }

    func testExposureMinus100Quarters() {
        // -100 exposure = -2 EV = 0.25x.
        let grade = resolveColorGrade(exposure: -100, contrast: 0, saturation: 0, warmth: 0, preset: .none, intensity: 0)
        let out = gradePixel(r: 0.8, g: 0.8, b: 0.8, grade: grade)
        XCTAssertEqual(out.r, 0.2, accuracy: 0.0001)
    }

    func testMonoPresetDesaturatesFully() {
        let grade = resolveColorGrade(exposure: 0, contrast: 0, saturation: 0, warmth: 0, preset: .mono, intensity: 1)
        XCTAssertEqual(grade.saturationFactor, 0, accuracy: 0.0001)
        let out = gradePixel(r: 0.8, g: 0.2, b: 0.2, grade: grade)
        // Grayscale: all channels equal the luma.
        XCTAssertEqual(out.r, out.g, accuracy: 0.0001)
        XCTAssertEqual(out.g, out.b, accuracy: 0.0001)
    }

    func testMonoPresetAtHalfIntensityHalvesSaturation() {
        let grade = resolveColorGrade(exposure: 0, contrast: 0, saturation: 0, warmth: 0, preset: .mono, intensity: 0.5)
        XCTAssertEqual(grade.saturationFactor, 0.5, accuracy: 0.0001)
    }

    func testVividPresetBoostsSaturationAndContrast() {
        let grade = resolveColorGrade(exposure: 0, contrast: 0, saturation: 0, warmth: 0, preset: .vivid, intensity: 1)
        XCTAssertEqual(grade.saturationFactor, 1.3, accuracy: 0.0001)
        XCTAssertEqual(grade.contrastFactor, 1.096, accuracy: 0.001)
    }

    func testPresetAtZeroIntensityIsNeutral() {
        let grade = resolveColorGrade(exposure: 0, contrast: 0, saturation: 0, warmth: 0, preset: .vivid, intensity: 0)
        XCTAssertEqual(grade.saturationFactor, 1, accuracy: 0.0001)
        XCTAssertEqual(grade.contrastFactor, 1, accuracy: 0.0001)
    }

    func testWarmthShiftsRedUpBlueDown() {
        let grade = resolveColorGrade(exposure: 0, contrast: 0, saturation: 0, warmth: 100, preset: .none, intensity: 0)
        let out = gradePixel(r: 0.5, g: 0.5, b: 0.5, grade: grade)
        XCTAssertGreaterThan(out.r, 0.5)
        XCTAssertLessThan(out.b, 0.5)
        XCTAssertEqual(out.g, 0.5, accuracy: 0.0001)
    }

    func testContrastKeepsMidGrey() {
        // Contrast pivots around 0.5, so mid grey is unchanged.
        let grade = resolveColorGrade(exposure: 0, contrast: 100, saturation: 0, warmth: 0, preset: .none, intensity: 0)
        let out = gradePixel(r: 0.5, g: 0.5, b: 0.5, grade: grade)
        XCTAssertEqual(out.r, 0.5, accuracy: 0.0001)
    }

    func testGradeClampsToUnitRange() {
        let grade = resolveColorGrade(exposure: 100, contrast: 100, saturation: 100, warmth: 100, preset: .vivid, intensity: 1)
        let out = gradePixel(r: 0.9, g: 0.9, b: 0.9, grade: grade)
        XCTAssertLessThanOrEqual(out.r, 1)
        XCTAssertLessThanOrEqual(out.g, 1)
        XCTAssertLessThanOrEqual(out.b, 1)
        XCTAssertGreaterThanOrEqual(out.r, 0)
    }

    func testCropRectFreeIsFullFrame() {
        let rect = cropRect(aspect: .free, sourceWidth: 4000, sourceHeight: 3000)
        XCTAssertEqual(rect.min, Vec2(0, 0))
        XCTAssertEqual(rect.size, Vec2(1, 1))
    }

    func testCropRectSquareOnLandscapeCropsWidth() {
        // 4:3 source, square target: width 0.75, centered.
        let rect = cropRect(aspect: .square, sourceWidth: 4000, sourceHeight: 3000)
        XCTAssertEqual(rect.size.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(rect.size.y, 1, accuracy: 0.0001)
        XCTAssertEqual(rect.min.x, 0.125, accuracy: 0.0001)
        XCTAssertEqual(rect.min.y, 0, accuracy: 0.0001)
    }

    func testCropRectWideOnPortraitCropsHeight() {
        // 3:4 source, 16:9 target: height = (3/4)/(16/9) = 0.421875.
        let rect = cropRect(aspect: .wide, sourceWidth: 3000, sourceHeight: 4000)
        XCTAssertEqual(rect.size.x, 1, accuracy: 0.0001)
        XCTAssertEqual(rect.size.y, 0.421875, accuracy: 0.0001)
        XCTAssertEqual(rect.min.y, (1 - 0.421875) / 2, accuracy: 0.0001)
    }
}
