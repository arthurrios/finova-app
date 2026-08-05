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
}
