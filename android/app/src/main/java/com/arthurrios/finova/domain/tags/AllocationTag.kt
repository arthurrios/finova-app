package com.arthurrios.finova.domain.tags

import com.arthurrios.finova.domain.model.TransactionCategory
import java.util.UUID

/**
 * A user-made group of spending categories ("Essentials", "Wealth"), so the budget card can show
 * what a whole set of categories costs. Port of AllocationTag.swift. A tag binds to categories,
 * never to one month's allocation; the mapping lives in [AllocationTagBook.categoryTagIds].
 *
 * @param iconCategory the category whose icon the tag shows; null means the default tag glyph.
 *   (iOS stores an asset name; Android reuses the category icons, which are the same set.)
 */
data class AllocationTag(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val colorIndex: Int,
    val iconCategory: TransactionCategory? = null,
    val sortOrder: Int,
) {
    val color: AllocationTagPalette.Entry get() = AllocationTagPalette.entry(colorIndex)
}

/**
 * Everything the tag feature stores: the tags and the category map, in one value, so a map entry
 * can never point at a deleted tag. Port of AllocationTagBook.
 */
data class AllocationTagBook(
    val tags: List<AllocationTag> = emptyList(),
    /** Category key to tag id. One tag per category, so the subtotals add up to the plan. */
    val categoryTagIds: Map<String, String> = emptyMap(),
) {
    val isEmpty: Boolean get() = tags.isEmpty()
    val orderedTags: List<AllocationTag> get() = tags.sortedWith(compareBy<AllocationTag> { it.sortOrder }.thenBy { it.id })

    fun tag(id: String): AllocationTag? = tags.firstOrNull { it.id == id }
    fun tagFor(category: TransactionCategory): AllocationTag? = categoryTagIds[category.key]?.let(::tag)
    fun categoryCount(tagId: String): Int = categoryTagIds.values.count { it == tagId }

    /** Drops what cannot be true (blank names, duplicate ids, links to missing tags). Applied on load and save. */
    fun sanitized(): AllocationTagBook {
        val validKeys = TransactionCategory.entries.map { it.key }.toSet()
        val seen = mutableSetOf<String>()
        val clean = mutableListOf<AllocationTag>()
        for (tag in tags.sortedBy { it.sortOrder }) {
            val name = tag.name.trim()
            if (name.isEmpty() || tag.id.isEmpty() || !seen.add(tag.id)) continue
            clean += tag.copy(name = name, colorIndex = AllocationTagPalette.clamp(tag.colorIndex), sortOrder = clean.size)
        }
        val live = clean.map { it.id }.toSet()
        return AllocationTagBook(clean, categoryTagIds.filter { (key, id) -> key in validKeys && id in live })
    }

    // ---- Changes (AllocationTagService) --------------------------------------------------------

    fun creating(name: String): Pair<AllocationTagBook, AllocationTag>? {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return null
        val tag = AllocationTag(name = trimmed, colorIndex = AllocationTagPalette.nextColorIndex(tags), sortOrder = tags.size)
        return copy(tags = tags + tag) to tag
    }

    fun updating(tagId: String, change: (AllocationTag) -> AllocationTag): AllocationTagBook =
        copy(tags = tags.map { if (it.id == tagId) change(it) else it })

    /** Removes the tag and its links. Allocations and transactions are untouched: a tag is only a lens. */
    fun deleting(tagId: String): AllocationTagBook =
        AllocationTagBook(tags.filterNot { it.id == tagId }, categoryTagIds.filterValues { it != tagId })

    /** The map is one-to-one, so this moves the category out of any other tag. */
    fun assigning(category: TransactionCategory, tagId: String): AllocationTagBook =
        if (tag(tagId) == null) this else copy(categoryTagIds = categoryTagIds + (category.key to tagId))

    fun unassigning(category: TransactionCategory): AllocationTagBook = copy(categoryTagIds = categoryTagIds - category.key)

    /** Ids not in [orderedIds] keep their relative order behind the ones that are. */
    fun reordering(orderedIds: List<String>): AllocationTagBook {
        val rank = orderedIds.withIndex().associate { it.value to it.index }
        return copy(
            tags = tags.sortedWith(compareBy<AllocationTag> { rank[it.id] ?: Int.MAX_VALUE }.thenBy { it.sortOrder })
                .mapIndexed { index, tag -> tag.copy(sortOrder = index) },
        )
    }

    companion object {
        /** Categories a tag can cover: every expense category (salary is income only). */
        val taggableCategories: List<TransactionCategory> get() = TransactionCategory.entries.filter { it != TransactionCategory.Salary }
    }
}
