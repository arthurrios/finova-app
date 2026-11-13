//
//  AllocationTagPalette.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

/// The fixed set of colours an allocation tag can take.
///
/// Fixed rather than free-form for three reasons: every tone has to stay legible on two very
/// different surfaces (see below), the tag ring sits 3pt inside a magenta category ramp and must not
/// collide with it, and a future group/cloud-backed tag book would otherwise have to negotiate
/// colours between devices. A stored index into this table sidesteps all of it.
enum AllocationTagPalette {

    /// A tag colour, in the two tones the app actually needs.
    ///
    /// One hex cannot serve both surfaces. The tag ring is drawn on `Colors.gradientBlack`, so it
    /// needs a *bright* tone; the chip strip and the tag list sit on `Colors.gray100`, and a selected
    /// chip fills with its tag colour and puts `gray100` text on top, so that needs a *dark* tone.
    /// The luminance windows for 3:1 on black and 4.5:1 on near-white do not overlap for any vivid
    /// hue. `CardColor` (`Core/Models/CreditCard.swift`) already splits a colour in two for the same
    /// kind of reason.
    struct Entry {
        let name: String
        /// For the tag ring on the dark card.
        let arc: UIColor
        /// For chips, dots and list rows on light surfaces.
        let ink: UIColor
    }

    /// Index order is storage order and must never be reordered - `AllocationTag.colorIndex` points
    /// into it. To change which colour a new tag gets first, edit `assignmentOrder`, not this.
    static let entries: [Entry] = [
        Entry(name: "sky", arc: UIColor(hex: "#38BDF8"), ink: UIColor(hex: "#075985")),
        Entry(name: "orange", arc: UIColor(hex: "#FB923C"), ink: UIColor(hex: "#C2410C")),
        Entry(name: "teal", arc: UIColor(hex: "#2DD4BF"), ink: UIColor(hex: "#115E59")),
        Entry(name: "rose", arc: UIColor(hex: "#FB7185"), ink: UIColor(hex: "#BE123C")),
        Entry(name: "lime", arc: UIColor(hex: "#A3E635"), ink: UIColor(hex: "#4D7C0F")),
        Entry(name: "indigo", arc: UIColor(hex: "#818CF8"), ink: UIColor(hex: "#4F46E5")),
        Entry(name: "green", arc: UIColor(hex: "#4ADE80"), ink: UIColor(hex: "#15803D")),
        Entry(name: "violet", arc: UIColor(hex: "#C084FC"), ink: UIColor(hex: "#7E22CE")),
    ]

    static var count: Int { entries.count }

    /// The order new tags claim colours in - chosen for hue spread, not for `entries` order.
    ///
    /// Hues: sky 198, orange 27, teal 173, rose 351, lime 83, indigo 235, green 142, violet 270.
    ///
    /// The first four are `indigo, lime, rose, teal`, which is the *only* four-subset of this palette
    /// whose members are all more than 60 apart (its tightest pair is teal/indigo at 62). That matters
    /// because most users will make two or three tags, and the 7pt ring gives colour alone to tell
    /// them apart - assigning `sky` then `teal`, only 26 apart, would have handed a user two arcs in
    /// the same cyan. `AllocationTagPaletteTests` asserts the 60 floor so this cannot regress.
    ///
    /// Violet is deliberately last: at 270 it is the closest entry to `Colors.mainMagenta` (299),
    /// which owns the category ramp sitting 3pt outside the tag ring.
    ///
    /// One adjacency worth knowing about rather than pretending away: `rose` (351) is close in hue to
    /// `Colors.brightRed` (0), `lime`'s ink tone reads as a green, and `orange` (27) is near
    /// `Colors.warningAmber` (38). None of those reserved colours is ever drawn on the tag ring - amber
    /// is the footer's over-allocation value and red/green live in the projection block - but on the
    /// light tag list a crimson or olive row still *reads* faintly like a status. Order within the
    /// first four is unconstrained by the 60-degree rule, so indigo and teal go first and the two
    /// status-adjacent tones come third and fourth.
    static let assignmentOrder: [Int] = [5, 2, 3, 4, 0, 1, 6, 7]

    /// Clamps any stored index onto the table, so a corrupt or downgraded value degrades to a
    /// wrong-but-valid colour instead of trapping.
    static func entry(at index: Int) -> Entry {
        entries[clampIndex(index)]
    }

    static func clampIndex(_ index: Int) -> Int {
        abs(index) % count
    }

    /// The colour a newly created tag should take: the first unclaimed one in `assignmentOrder`.
    ///
    /// Past eight tags it returns the least-used index, ties broken by assignment order. Pure and
    /// deterministic on purpose - deleting a tag frees its colour for the next one, which is what a
    /// user expects after deleting and recreating.
    static func nextColorIndex(existing: [AllocationTag]) -> Int {
        var uses = [Int](repeating: 0, count: count)
        for tag in existing {
            uses[clampIndex(tag.colorIndex)] += 1
        }

        var best = assignmentOrder.first ?? 0
        var bestUses = Int.max
        for index in assignmentOrder where uses[index] < bestUses {
            best = index
            bestUses = uses[index]
            if bestUses == 0 { break }
        }
        return best
    }
}
