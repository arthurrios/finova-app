//
//  AllocationTagService.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import Foundation

/// The only type UI touches to read or change allocation tags.
///
/// Holds the decoded book in memory because the dashboard needs the category map on every rebuild -
/// per visible carousel cell, per layout pass - and decoding a blob there would be wasteful. The cache
/// is dropped whenever the signed-in uid changes, so switching accounts can never show the previous
/// account's grouping.
final class AllocationTagService {

    static let shared = AllocationTagService()

    private let store: AllocationTagStoring
    private let uidProvider: () -> String?

    private var cached: AllocationTagBook?
    /// The uid `cached` was loaded under, so an account switch invalidates rather than persists.
    private var cachedUid: String?

    init(
        store: AllocationTagStoring = UserDefaultsAllocationTagStore(),
        uidProvider: @escaping () -> String? = { UIDUserDefaultsManager.shared.currentUserUID }
    ) {
        self.store = store
        self.uidProvider = uidProvider
    }

    // MARK: - Reading

    var book: AllocationTagBook {
        let uid = uidProvider()
        if let cached, cachedUid == uid { return cached }

        let loaded = store.load()
        cached = loaded
        cachedUid = uid
        return loaded
    }

    var tags: [AllocationTag] { book.orderedTags }

    var hasTags: Bool { !book.tags.isEmpty }

    func tag(id: String) -> AllocationTag? { book.tag(id: id) }

    func tag(forCategoryKey key: String) -> AllocationTag? {
        guard let id = book.tagId(forCategoryKey: key) else { return nil }
        return book.tag(id: id)
    }

    func categoryKeys(forTagId tagId: String) -> [String] {
        book.categoryKeys(forTagId: tagId)
    }

    func categoryCount(forTagId tagId: String) -> Int {
        book.categoryTagIds.values.reduce(0) { $0 + ($1 == tagId ? 1 : 0) }
    }

    /// Drops the in-memory copy. Call on sign-in/sign-out, where the uid changes outside our sight.
    func invalidateCache() {
        cached = nil
        cachedUid = nil
    }

    // MARK: - Writing

    @discardableResult
    func createTag(name: String) -> AllocationTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var current = book
        let tag = AllocationTag(
            name: trimmed,
            colorIndex: AllocationTagPalette.nextColorIndex(existing: current.tags),
            sortOrder: current.tags.count
        )
        current.tags.append(tag)
        commit(current)
        return tag
    }

    func rename(tagId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateTag(tagId) { $0.name = trimmed }
    }

    func setColorIndex(_ index: Int, forTagId tagId: String) {
        mutateTag(tagId) { $0.colorIndex = AllocationTagPalette.clampIndex(index) }
    }

    /// `nil` restores the default glyph.
    func setIconAssetName(_ assetName: String?, forTagId tagId: String) {
        mutateTag(tagId) { $0.iconAssetName = assetName }
    }

    /// Removes the tag and every category link pointing at it. Allocations and transactions are
    /// untouched - a tag is a lens over them, never their owner.
    func deleteTag(id tagId: String) {
        var current = book
        current.tags.removeAll { $0.id == tagId }
        current.categoryTagIds = current.categoryTagIds.filter { $0.value != tagId }
        commit(current)
    }

    /// Assigns a category to a tag. The map is 1:1, so this *moves* the category out of whatever tag
    /// held it - the callers that need to warn about that ask `tag(forCategoryKey:)` first.
    func assign(categoryKey: String, toTagId tagId: String) {
        guard book.tag(id: tagId) != nil else { return }
        var current = book
        current.categoryTagIds[categoryKey] = tagId
        commit(current)
    }

    func unassign(categoryKey: String) {
        var current = book
        current.categoryTagIds.removeValue(forKey: categoryKey)
        commit(current)
    }

    /// `orderedIds` is the new display order; ids not present keep their relative order behind them.
    func reorder(tagIds orderedIds: [String]) {
        var current = book
        let rank = Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($1, $0) })
        current.tags = current.tags
            .sorted { lhs, rhs in
                let l = rank[lhs.id] ?? Int.max
                let r = rank[rhs.id] ?? Int.max
                return l == r ? lhs.sortOrder < rhs.sortOrder : l < r
            }
            .enumerated()
            .map { index, tag in
                var copy = tag
                copy.sortOrder = index
                return copy
            }
        commit(current)
    }

    // MARK: - Plumbing

    private func mutateTag(_ tagId: String, _ change: (inout AllocationTag) -> Void) {
        var current = book
        guard let index = current.tags.firstIndex(where: { $0.id == tagId }) else { return }
        change(&current.tags[index])
        commit(current)
    }

    /// Single write path: persist, refresh the cache from what was actually stored (so callers see the
    /// sanitised truth rather than their own optimistic copy), then notify.
    private func commit(_ book: AllocationTagBook) {
        store.save(book)
        cached = nil
        cachedUid = nil
        _ = self.book

        NotificationCenter.default.post(name: .allocationTagsChanged, object: nil)
    }
}
