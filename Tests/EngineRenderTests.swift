import XCTest
import UIKit
@testable import Lustra

final class EngineRenderTests: XCTestCase {
    func testStatsFindTheHair() {
        let (ctx, _, matte) = Synthetic.context()
        XCTAssertTrue(ctx.stats.hasHair)
        XCTAssertGreaterThan(ctx.stats.coverage, 0.15)
        XCTAssertLessThan(ctx.stats.coverage, 0.6)
        XCTAssertLessThan(ctx.stats.top, 0.2)
        XCTAssertGreaterThan(ctx.stats.bottom, 0.5)
        XCTAssertGreaterThan(matte.sum, 1000)
    }

    func testPixelsOutsideTheMatteAreUntouched() {
        let (ctx, img, matte) = Synthetic.context()
        var look = HairLook.default
        look.primary = HairColor(hex: 0xC2307F)
        let out = ctx.render(look)
        var changedOutside = 0
        for i in 0..<(img.width * img.height) where matte.data[i] < 0.01 {
            if out.pixels[i * 4] != img.pixels[i * 4] || out.pixels[i * 4 + 1] != img.pixels[i * 4 + 1] || out.pixels[i * 4 + 2] != img.pixels[i * 4 + 2] {
                changedOutside += 1
            }
        }
        XCTAssertEqual(changedOutside, 0)
    }

    func testRecolourMovesHairTowardsTheTargetHue() {
        let (ctx, img, matte) = Synthetic.context()
        let before = Synthetic.meanLab(img, matte: matte)
        for hex in [UInt32(0x2B79E0), 0xC2307F, 0x1B7F52] {
            var look = HairLook.default
            look.primary = HairColor(hex: hex)
            look.intensity = 1
            let out = ctx.render(look)
            let after = Synthetic.meanLab(out, matte: matte)
            let target = look.primary.lab
            let hAfter = atan2f(after.b, after.a), hTarget = atan2f(target.b, target.a)
            var d = abs(hAfter - hTarget)
            if d > .pi { d = 2 * .pi - d }
            XCTAssertLessThan(d, 0.5, "hue off for \(String(hex, radix: 16)); before \(before) after \(after)")
        }
    }

    func testDarkToLightKeepsStrandDetail() {
        let (ctx, img, matte) = Synthetic.context()
        var look = HairLook.default
        look.primary = HairColor(hex: 0xDDBA6E)
        look.intensity = 1
        let out = ctx.render(look)
        let after = Synthetic.meanLab(out, matte: matte)
        XCTAssertGreaterThan(after.L, 55, "blonde should be light")
        func sd(_ im: RGBAImage) -> Float {
            var s: Double = 0, s2: Double = 0, n = 0
            for i in 0..<(im.width * im.height) where matte.data[i] > 0.9 {
                let L = Double(ColorMath.lab(r: im.pixels[i * 4], g: im.pixels[i * 4 + 1], b: im.pixels[i * 4 + 2]).L)
                s += L; s2 += L * L; n += 1
            }
            let m = s / Double(n)
            return Float((s2 / Double(n) - m * m).squareRoot())
        }
        XCTAssertGreaterThan(sd(out), sd(img) * 0.7)
    }

    func testIntensityZeroLeavesPhotoAlone() {
        let (ctx, img, _) = Synthetic.context()
        var look = HairLook.default
        look.intensity = 0
        let out = ctx.render(look)
        XCTAssertEqual(out.pixels, img.pixels)
    }

    func testOmbreIsDarkerAtTheRootsThanTheTips() {
        let (ctx, _, matte) = Synthetic.context()
        var look = HairLook.default
        look.style = .ombre
        look.primary = HairColor(hex: 0x2E1C14)
        look.secondary = HairColor(hex: 0xDDBA6E)
        look.intensity = 1
        look.gradientStart = 0.3
        let out = ctx.render(look)
        func meanL(rows: ClosedRange<Int>) -> Float {
            var s: Float = 0
            var n = 0
            for y in rows {
                for x in 0..<out.width where matte[x, y] > 0.9 {
                    let i = y * out.width + x
                    s += ColorMath.lab(r: out.pixels[i * 4], g: out.pixels[i * 4 + 1], b: out.pixels[i * 4 + 2]).L
                    n += 1
                }
            }
            return n > 0 ? s / Float(n) : 0
        }
        XCTAssertLessThan(meanL(rows: 40...80) + 8, meanL(rows: 250...300))
    }

    func testGrayCoverOnlyColoursLightNeutralStrands() {
        var (img, matte) = Synthetic.portrait()
        for y in 0..<img.height {
            for x in 0..<200 where matte[x, y] > 0.9 {
                let i = (y * img.width + x) * 4
                let v = UInt8(150 + (x % 7) * 3)
                img.pixels[i] = v; img.pixels[i + 1] = v; img.pixels[i + 2] = v
            }
        }
        let ctx = HairContext(planes: PhotoPlanes(image: img), matte: matte)
        var look = HairLook.default
        look.primary = HairColor(hex: 0x6C42C2)
        look.intensity = 1
        look.grayCoverOnly = true
        let out = ctx.render(look)
        var leftChange = 0, rightChange = 0
        for y in 0..<img.height {
            for x in 0..<img.width where matte[x, y] > 0.9 {
                let i = (y * img.width + x) * 4
                let d = abs(Int(out.pixels[i]) - Int(img.pixels[i])) + abs(Int(out.pixels[i + 2]) - Int(img.pixels[i + 2]))
                if d > 30 { if x < 200 { leftChange += 1 } else { rightChange += 1 } }
            }
        }
        XCTAssertGreaterThan(leftChange, rightChange * 5)
        matte.clamp01()
    }

    func testRenderIsDeterministic() {
        let (ctx, _, _) = Synthetic.context()
        var look = HairLook.default
        look.style = .balayage
        look.secondary = HairColor(hex: 0xF0E0B0)
        XCTAssertEqual(ctx.render(look).pixels, ctx.render(look).pixels)
    }

    func testSanitizedLookNeverProducesNaN() {
        var look = HairLook.default
        look.intensity = .nan
        look.shine = 40
        look.brightness = -9
        let s = look.sanitized()
        XCTAssertEqual(s.intensity, 0)
        XCTAssertEqual(s.shine, 1)
        XCTAssertEqual(s.brightness, -1)
    }

    func testGuidedFilterKeepsFlatRegions() {
        let guide = Plane(width: 64, height: 64, fill: 0.5)
        let input = Plane(width: 64, height: 64, fill: 1)
        let q = PlaneOps.guidedFilter(guide: guide, input: input, radius: 4, eps: 1e-3)
        XCTAssertEqual(q.mean, 1, accuracy: 0.01)
    }

    func testBrushAddsAndRemovesHair() {
        var base = Plane(width: 100, height: 100)
        let add = BrushStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1, addsHair: true, hardness: 1)
        base = MatteRefiner.apply([add], to: base)
        XCTAssertEqual(base[50, 50], 1, accuracy: 0.01)
        XCTAssertEqual(base[5, 5], 0, accuracy: 0.001)
        let remove = BrushStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.05, addsHair: false, hardness: 1)
        let after = MatteRefiner.apply([remove], to: base)
        XCTAssertEqual(after[50, 50], 0, accuracy: 0.01)
        XCTAssertGreaterThan(after[56, 50], 0.5)
    }

    func testEditHistoryUndoRedoAndLiveDrags() {
        var h = EditHistory(initial: 1)
        h.live(2)
        h.live(3)
        h.endLive()
        XCTAssertEqual(h.present, 3)
        h.commit(4)
        XCTAssertTrue(h.canUndo)
        h.undo()
        XCTAssertEqual(h.present, 3)
        h.undo()
        XCTAssertEqual(h.present, 1)
        XCTAssertFalse(h.canUndo)
        h.redo()
        XCTAssertEqual(h.present, 3)
        h.commit(9)
        XCTAssertFalse(h.canRedo)
    }

    func testLabRoundTrip() {
        for rgb in [(10, 20, 30), (255, 255, 255), (0, 0, 0), (200, 120, 40), (90, 200, 60)] {
            let lab = ColorMath.lab(r: UInt8(rgb.0), g: UInt8(rgb.1), b: UInt8(rgb.2))
            let back = ColorMath.srgb(L: lab.L, a: lab.a, b: lab.b)
            XCTAssertEqual(Int(back.r), rgb.0, accuracy: 2)
            XCTAssertEqual(Int(back.g), rgb.1, accuracy: 2)
            XCTAssertEqual(Int(back.b), rgb.2, accuracy: 2)
        }
    }
}
