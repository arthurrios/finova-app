//
//  AllocationTag.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

// MARK: - Tag

/// A user-created grouping of spending categories - "Essentials", "Wealth" - so the budget card can
/// report what a whole set of categories costs in a month.
///
/// A tag binds to *categories*, never to a single month's allocation. Rent is an essential in every
/// month, so asking the question per allocation row would mean answering it twelve times a year. The
/// mapping lives in `AllocationTagBook.categoryTagIds`; this type is only the tag's identity.
struct AllocationTag: Codable, Equatable, Identifiable {

    let id: String
    var name: String
    /// Index into `AllocationTagPalette.entries`. Stored rather than a hex string so the palette can
    /// be retuned in one place and a corrupt value can be clamped instead of failing to parse.
    var colorIndex: Int
    /// A `lucide_icon*` asset name. `nil` means the default glyph, which is the documented default
    /// rather than a magic string.
    var iconAssetName: String?
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        colorIndex: Int,
        iconAssetName: String? = nil,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.iconAssetName = iconAssetName
        self.sortOrder = sortOrder
    }

    var color: AllocationTagPalette.Entry {
        AllocationTagPalette.entry(at: colorIndex)
    }

    /// Resolved at read time, not stored: an asset can vanish between app versions, and a missing
    /// image would otherwise render as a blank square.
    var icon: Icon {
        if let iconAssetName, UIImage(named: iconAssetName) != nil {
            return .asset(iconAssetName)
        }
        return .systemSymbol(Self.defaultSymbolName)
    }

    /// There is no `lucide_iconTag` asset, and the card already mixes SF Symbols in for exactly this
    /// kind of gap (`questionmark.circle` on the donut, `creditcard.fill` in the card header).
    static let defaultSymbolName = "tag.fill"

    enum Icon: Equatable {
        case asset(String)
        case systemSymbol(String)

        var image: UIImage? {
            switch self {
            case .asset(let name):
                return UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
            case .systemSymbol(let name):
                return UIImage(systemName: name)
            }
        }
    }
}

// MARK: - Book

/// Everything the tag feature persists: the catalog and the category mapping, in one value.
///
/// One blob rather than two stores because the two halves are only ever read together and must never
/// disagree - a map entry pointing at a deleted tag is the one corruption worth designing out.
struct AllocationTagBook: Codable, Equatable {

    /// Payload version. The storage *key* is versioned too; see `AllocationTagStore`.
    var schemaVersion: Int
    var tags: [AllocationTag]
    /// `TransactionCategory.key` -> `AllocationTag.id`. One tag per category: exclusive tags
    /// partition the plan, which is what lets the subtotals add up to the budget and the donut render
    /// them as contiguous arcs.
    var categoryTagIds: [String: String]
    /// Unused in v1. Present from the start because a cloud-backed store needs a last-writer-wins
    /// field, and adding one later would be a schema change.
    var updatedAt: Date

    static let currentSchemaVersion = 1

    static let empty = AllocationTagBook(
        schemaVersion: currentSchemaVersion,
        tags: [],
        categoryTagIds: [:],
        updatedAt: .distantPast
    )

    var isEmpty: Bool { tags.isEmpty }

    /// Tags in display order.
    var orderedTags: [AllocationTag] {
        tags.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
        }
    }

    func tag(id: String) -> AllocationTag? {
        tags.first { $0.id == id }
    }

    func tagId(forCategoryKey key: String) -> String? {
        categoryTagIds[key]
    }

    func categoryKeys(forTagId tagId: String) -> [String] {
        categoryTagIds.filter { $0.value == tagId }.keys.sorted()
    }

    /// Drops everything that cannot be true, so no reader downstream has to defend against it.
    ///
    /// Applied on every load, so it also repairs a book written by a buggy or interrupted earlier
    /// version rather than only guarding fresh input.
    func sanitized() -> AllocationTagBook {
        let validCategoryKeys = Set(TransactionCategory.allCases.map { $0.key })

        var seenIds = Set<String>()
        var cleanTags: [AllocationTag] = []
        for tag in tags.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !tag.id.isEmpty, seenIds.insert(tag.id).inserted else { continue }

            var clean = tag
            clean.name = name
            clean.colorIndex = AllocationTagPalette.clampIndex(tag.colorIndex)
            if let asset = tag.iconAssetName, UIImage(named: asset) == nil {
                clean.iconAssetName = nil
            }
            // Densified rather than preserved: gaps and duplicates in sortOrder make reordering
            // ambiguous, and the sorted() above already fixed the relative order.
            clean.sortOrder = cleanTags.count
            cleanTags.append(clean)
        }

        let liveIds = Set(cleanTags.map { $0.id })
        let cleanMap = categoryTagIds.filter { key, tagId in
            validCategoryKeys.contains(key) && liveIds.contains(tagId)
        }

        return AllocationTagBook(
            schemaVersion: Self.currentSchemaVersion,
            tags: cleanTags,
            categoryTagIds: cleanMap,
            updatedAt: updatedAt
        )
    }
}
