package com.arthurrios.finova.data.repo

import android.content.Context
import android.util.Log
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.tags.AllocationTag
import com.arthurrios.finova.domain.tags.AllocationTagBook
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * The tag book for one account, kept on this device. Port of AllocationTagService and
 * UserDefaultsAllocationTagStore: one JSON value per uid. A value it cannot read is never
 * overwritten, since it may hold the user's tags in a newer format.
 */
class TagRepository(context: Context, val uid: String) {
    private val prefs = context.getSharedPreferences("allocation_tags", Context.MODE_PRIVATE)
    private val key = "allocationTagBook_v1_$uid"
    private var readOnly = false
    private val state = MutableStateFlow(load())

    val book: StateFlow<AllocationTagBook> = state

    fun create(name: String): AllocationTag? {
        val (next, tag) = state.value.creating(name) ?: return null
        commit(next)
        return tag
    }

    fun rename(tagId: String, name: String) {
        if (name.isBlank()) return
        commit(state.value.updating(tagId) { it.copy(name = name.trim()) })
    }

    fun setColor(tagId: String, index: Int) = commit(state.value.updating(tagId) { it.copy(colorIndex = index) })
    fun setIcon(tagId: String, category: TransactionCategory?) = commit(state.value.updating(tagId) { it.copy(iconCategory = category) })
    fun delete(tagId: String) = commit(state.value.deleting(tagId))
    fun assign(category: TransactionCategory, tagId: String) = commit(state.value.assigning(category, tagId))
    fun unassign(category: TransactionCategory) = commit(state.value.unassigning(category))
    fun reorder(ids: List<String>) = commit(state.value.reordering(ids))

    private fun commit(book: AllocationTagBook) {
        val clean = book.sanitized()
        state.value = clean
        if (readOnly) {
            Log.w(TAG, "Refusing to write over a tag book that could not be read")
            return
        }
        prefs.edit().putString(key, encode(clean)).apply()
    }

    private fun load(): AllocationTagBook {
        val raw = prefs.getString(key, null) ?: return AllocationTagBook()
        return runCatching {
            val json = JSONObject(raw)
            if (json.optInt("schemaVersion", 1) > SCHEMA_VERSION) readOnly = true
            decode(json).sanitized()
        }.getOrElse {
            Log.e(TAG, "Could not read the tag book; keeping the stored value", it)
            readOnly = true
            AllocationTagBook()
        }
    }

    private fun encode(book: AllocationTagBook): String = JSONObject().apply {
        put("schemaVersion", SCHEMA_VERSION)
        put("tags", JSONArray().apply {
            book.tags.forEach { tag ->
                put(JSONObject().apply {
                    put("id", tag.id)
                    put("name", tag.name)
                    put("colorIndex", tag.colorIndex)
                    tag.iconCategory?.let { put("iconCategory", it.key) }
                    put("sortOrder", tag.sortOrder)
                })
            }
        })
        put("categoryTagIds", JSONObject(book.categoryTagIds))
        put("updatedAt", System.currentTimeMillis())
    }.toString()

    private fun decode(json: JSONObject): AllocationTagBook {
        val tags = json.getJSONArray("tags").let { array ->
            (0 until array.length()).map { i ->
                val t = array.getJSONObject(i)
                AllocationTag(
                    id = t.getString("id"),
                    name = t.getString("name"),
                    colorIndex = t.optInt("colorIndex"),
                    iconCategory = t.optString("iconCategory").takeIf { it.isNotEmpty() }
                        ?.let { key -> TransactionCategory.entries.firstOrNull { it.key == key } },
                    sortOrder = t.optInt("sortOrder"),
                )
            }
        }
        val map = json.optJSONObject("categoryTagIds")?.let { o -> o.keys().asSequence().associateWith { o.getString(it) } }.orEmpty()
        return AllocationTagBook(tags, map)
    }

    fun removeAll() = prefs.edit().remove(key).apply()

    private companion object {
        const val TAG = "AllocationTags"
        const val SCHEMA_VERSION = 1
    }
}
