package com.arthurrios.finova.ui.tags

import androidx.lifecycle.ViewModel
import com.arthurrios.finova.data.repo.TagRepository
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.tags.AllocationTag
import com.arthurrios.finova.domain.tags.AllocationTagBook
import kotlinx.coroutines.flow.StateFlow

/**
 * Shared by the three tag screens (list, edit, categories). Port of AllocationTagsViewModel and the
 * two tag view controllers; every change goes straight to [TagRepository], so the dashboard updates
 * at once.
 */
class TagsViewModel(private val tags: TagRepository) : ViewModel() {
    val book: StateFlow<AllocationTagBook> = tags.book

    fun create(name: String): AllocationTag? = tags.create(name)
    fun delete(tagId: String) = tags.delete(tagId)
    fun reorder(ids: List<String>) = tags.reorder(ids)
    fun rename(tagId: String, name: String) = tags.rename(tagId, name)
    fun setColor(tagId: String, index: Int) = tags.setColor(tagId, index)
    fun setIcon(tagId: String, category: TransactionCategory?) = tags.setIcon(tagId, category)

    /** Adds or removes a category. Moving one out of another tag is confirmed by the screen first. */
    fun toggle(tagId: String, category: TransactionCategory) {
        if (book.value.tagFor(category)?.id == tagId) tags.unassign(category) else tags.assign(category, tagId)
    }
}
