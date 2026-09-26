package com.arthurrios.finova.domain.tags

import kotlin.math.abs

/**
 * The fixed tag colours. Port of AllocationTagPalette.swift. Each has two tones: [Entry.arc], bright,
 * for the ring on the dark card, and [Entry.ink], dark, for chips and rows on light surfaces.
 * Index order is storage order and must never change.
 */
object AllocationTagPalette {
    data class Entry(val name: String, val arc: Long, val ink: Long)

    val entries = listOf(
        Entry("sky", 0xFF38BDF8, 0xFF075985),
        Entry("orange", 0xFFFB923C, 0xFFC2410C),
        Entry("teal", 0xFF2DD4BF, 0xFF115E59),
        Entry("rose", 0xFFFB7185, 0xFFBE123C),
        Entry("lime", 0xFFA3E635, 0xFF4D7C0F),
        Entry("indigo", 0xFF818CF8, 0xFF4F46E5),
        Entry("green", 0xFF4ADE80, 0xFF15803D),
        Entry("violet", 0xFFC084FC, 0xFF7E22CE),
    )

    /** The order new tags take colours in, chosen for hue spread (see the iOS notes). */
    val assignmentOrder = listOf(5, 2, 3, 4, 0, 1, 6, 7)

    fun clamp(index: Int): Int = abs(index) % entries.size
    fun entry(index: Int): Entry = entries[clamp(index)]

    /** The first unused colour in [assignmentOrder]; past eight tags, the least used one. */
    fun nextColorIndex(existing: List<AllocationTag>): Int {
        val uses = IntArray(entries.size)
        existing.forEach { uses[clamp(it.colorIndex)]++ }
        var best = assignmentOrder.first()
        var bestUses = Int.MAX_VALUE
        for (index in assignmentOrder) {
            if (uses[index] < bestUses) {
                best = index
                bestUses = uses[index]
                if (bestUses == 0) break
            }
        }
        return best
    }
}
