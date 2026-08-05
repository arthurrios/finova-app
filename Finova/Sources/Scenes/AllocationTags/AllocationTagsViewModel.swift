//
//  AllocationTagsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import Foundation

final class AllocationTagsViewModel {

    private let tagService: AllocationTagService

    private(set) var tags: [AllocationTag] = []

    var onTagsUpdated: (() -> Void)?

    var isEmpty: Bool { tags.isEmpty }

    init(tagService: AllocationTagService = .shared) {
        self.tagService = tagService
    }

    func loadTags() {
        tags = tagService.tags
        onTagsUpdated?()
    }

    func categoryCount(for tag: AllocationTag) -> Int {
        tagService.categoryCount(forTagId: tag.id)
    }

    /// Returns the created tag so the caller can push straight into editing it.
    func createTag(name: String) -> AllocationTag? {
        let tag = tagService.createTag(name: name)
        loadTags()
        return tag
    }

    func deleteTag(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tagService.deleteTag(id: tags[index].id)
        loadTags()
    }

    /// Moves a tag and persists the new order.
    ///
    /// Deliberately does NOT call `loadTags()`. The table has already animated the row into place, and
    /// a `reloadData()` on top of that both cancels the animation and fights the drop coordinator's
    /// own placement. The local array is updated to match what the user just did, so the two agree
    /// without a reload.
    func moveTag(from source: Int, to destination: Int) {
        guard tags.indices.contains(source), tags.indices.contains(destination),
            source != destination
        else { return }

        var reordered = tags
        reordered.insert(reordered.remove(at: source), at: destination)
        tags = reordered
        // The service densifies `sortOrder` from this array's order, so the ids alone are enough.
        tagService.reorder(tagIds: reordered.map(\.id))
    }
}
