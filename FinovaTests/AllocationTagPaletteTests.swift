//
//  AllocationTagPaletteTests.swift
//  FinovaTests
//
//  The tag palette has to stay legible on the dark budget card AND on the light chip strip, and must
//  never collide with the colours that already carry meaning on that card. These assertions are the
//  reason those claims survive a future palette edit.
//

import UIKit
import XCTest

@testable import Finova

final class AllocationTagPaletteTests: XCTestCase {

    // MARK: - Contrast helper

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let l1 = luminance(lhs), l2 = luminance(rhs)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func hue(_ color: UIColor) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h * 360
    }

    /// The lighter stop of `Colors.gradientBlack`. The ring crosses both stops, so this is the worst
    /// case for an arc tone - not the near-black one.
    private let lighterCardStop = UIColor(hex: "#2D2D2D")

    // MARK: - Structure

    func testPaletteHasEightEntries() {
        XCTAssertEqual(AllocationTagPalette.entries.count, 8)
        XCTAssertEqual(AllocationTagPalette.count, 8)
    }

    func testAssignmentOrderIsAPermutationOfEveryIndex() {
        XCTAssertEqual(
            AllocationTagPalette.assignmentOrder.sorted(),
            Array(0..<AllocationTagPalette.count),
            "every colour must be reachable, and none twice")
    }

    func testIndexesAreClampedOntoTheTable() {
        for candidate in [-99, -8, -1, 0, 7, 8, 99] {
            let clamped = AllocationTagPalette.clampIndex(candidate)
            XCTAssertTrue((0..<AllocationTagPalette.count).contains(clamped), "\(candidate) -> \(clamped)")
        }
    }

    // MARK: - Contrast

    /// A non-text graphical object needs 3:1. Every arc tone must clear that against the *lighter*
    /// gradient stop, or the ring disappears into the card on one side.
    func testArcTonesAreLegibleOnTheDarkCard() {
        for entry in AllocationTagPalette.entries {
            let ratio = contrast(entry.arc, lighterCardStop)
            XCTAssertGreaterThanOrEqual(
                ratio, 3.0, "\(entry.name) arc is \(String(format: "%.2f", ratio)):1 on #2D2D2D")
        }
    }

    /// A selected chip fills with its `ink` tone and puts `gray100` text on top, so these have to clear
    /// the 4.5:1 small-text bar, not just the 3:1 graphical one.
    func testInkTonesCarryLightTextAndReadOnLightSurfaces() {
        for entry in AllocationTagPalette.entries {
            let onSurface = contrast(entry.ink, Colors.gray100)
            XCTAssertGreaterThanOrEqual(
                onSurface, 4.5, "\(entry.name) ink is \(String(format: "%.2f", onSurface)):1 on gray100")
        }
    }

    /// The tag ring is brighter than the neutrals already on that band, which is what makes it read as
    /// a chromatic accent rather than more grey.
    func testArcTonesOutshineTheGreysAlreadyOnTheRing() {
        let unallocated = contrast(Colors.gray600, lighterCardStop)
        for entry in AllocationTagPalette.entries {
            XCTAssertGreaterThan(contrast(entry.arc, lighterCardStop), unallocated, entry.name)
        }
    }

    // MARK: - Collisions

    /// Four colours already carry meaning on this exact card: the magenta category ramp, amber
    /// over-allocation, and the green/red projection verdict. A tag that matched one would be read as
    /// a status.
    func testNoPaletteToneCollidesWithAColourThatAlreadyMeansSomething() {
        let reserved: [(String, UIColor)] = [
            ("mainMagenta", Colors.mainMagenta),
            ("warningAmber", Colors.warningAmber),
            ("brightGreen", Colors.brightGreen),
            ("brightRed", Colors.brightRed),
            ("mainRed", Colors.mainRed),
            ("mainGreen", Colors.mainGreen),
        ]

        for entry in AllocationTagPalette.entries {
            for (name, color) in reserved {
                XCTAssertFalse(
                    entry.arc.isSameRGB(as: color), "\(entry.name) arc is exactly \(name)")
                XCTAssertFalse(
                    entry.ink.isSameRGB(as: color), "\(entry.name) ink is exactly \(name)")
            }
        }
    }

    /// Violet is the closest entry to the magenta category ramp that sits 3pt outside the tag ring, so
    /// it must be the *last* colour a new tag claims.
    func testTheHueNearestTheCategoryRampIsClaimedLast() {
        let magentaHue = hue(Colors.mainMagenta)
        let distances = AllocationTagPalette.entries.map { entry -> CGFloat in
            let delta = abs(hue(entry.arc) - magentaHue)
            return min(delta, 360 - delta)
        }
        let nearest = distances.enumerated().min { $0.element < $1.element }!.offset

        XCTAssertEqual(
            AllocationTagPalette.assignmentOrder.last, nearest,
            "\(AllocationTagPalette.entries[nearest].name) is nearest mainMagenta and must be assigned last")
    }

    /// The first few tags are the common case, so they are the ones that have to be unmistakable from
    /// each other at 7pt.
    func testTheFirstFourColoursAreWellSpreadInHue() {
        let firstFour = AllocationTagPalette.assignmentOrder.prefix(4)
            .map { hue(AllocationTagPalette.entries[$0].arc) }

        for (i, a) in firstFour.enumerated() {
            for b in firstFour.dropFirst(i + 1) {
                let delta = abs(a - b)
                XCTAssertGreaterThan(
                    min(delta, 360 - delta), 60,
                    "hues \(Int(a)) and \(Int(b)) are too close for the first four tags")
            }
        }
    }
}

private extension UIColor {
    func isSameRGB(as other: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.001 && abs(g1 - g2) < 0.001 && abs(b1 - b2) < 0.001
    }
}
