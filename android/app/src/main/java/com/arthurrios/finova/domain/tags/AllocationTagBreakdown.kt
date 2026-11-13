package com.arthurrios.finova.domain.tags

import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.UnallocatedSpending
import com.arthurrios.finova.domain.model.TransactionCategory

/**
 * The donut's slice order and its tag ring. Port of AllocationTagBreakdown.swift. Slices are grouped
 * by tag (in the user's tag order), then untagged ones, then unallocated headroom last, so each tag's
 * slices are one contiguous arc from 12 o'clock.
 */
class AllocationTagBreakdown private constructor(
    val segments: List<Segment>,
    val tagArcs: List<TagArc>,
    /** Null when nothing is tagged, or everything is. */
    val untagged: Bucket?,
    val headroom: Long,
    val angularTotal: Long,
    val totalBudget: Long,
) {
    sealed interface Kind {
        data class Allocated(val category: TransactionCategory) : Kind
        data class OffPlan(val category: TransactionCategory) : Kind
        data object Headroom : Kind
    }

    data class Segment(val id: String, val kind: Kind, val amount: Long, val tagId: String?) {
        val category: TransactionCategory?
            get() = when (kind) {
                is Kind.Allocated -> kind.category
                is Kind.OffPlan -> kind.category
                Kind.Headroom -> null
            }
    }

    data class Bucket(
        val allocated: Long,
        val used: Long,
        val offPlan: Long,
        /** How much of the budget cap this group plans to use; off-plan spending does not count. */
        val share: Double,
    )

    data class TagArc(
        val tag: AllocationTag,
        val bucket: Bucket,
        val memberSegmentIds: Set<String>,
        val startFraction: Double,
        val endFraction: Double,
    )

    val hasTags: Boolean get() = tagArcs.isNotEmpty()
    fun arc(tagId: String): TagArc? = tagArcs.firstOrNull { it.tag.id == tagId }
    fun segmentBelongsTo(segmentId: String, tagId: String): Boolean = arc(tagId)?.memberSegmentIds?.contains(segmentId) == true

    companion object {
        fun of(
            allocations: List<BudgetAllocation>,
            unallocatedSpending: List<UnallocatedSpending>,
            unallocatedHeadroom: Long,
            totalBudget: Long,
            book: AllocationTagBook,
        ): AllocationTagBreakdown {
            val headroom = unallocatedHeadroom.coerceAtLeast(0)
            val liveIds = book.tags.map { it.id }.toSet()
            fun tagOf(category: TransactionCategory) = book.categoryTagIds[category.key]?.takeIf { it in liveIds }

            val allocationsByTag = allocations.filter { tagOf(it.category) != null }.groupBy { tagOf(it.category)!! }
            val spendingByTag = unallocatedSpending.filter { tagOf(it.category) != null }.groupBy { tagOf(it.category)!! }
            val untaggedAllocations = allocations.filter { tagOf(it.category) == null }
            val untaggedSpending = unallocatedSpending.filter { tagOf(it.category) == null }
            val total = allocations.sumOf { it.allocated } + unallocatedSpending.sumOf { it.spent } + headroom

            // Only tags with money this month get an arc; the user's order, then id.
            val ordered = book.orderedTags.filter { allocationsByTag[it.id].orEmpty().isNotEmpty() || spendingByTag[it.id].orEmpty().isNotEmpty() }
            val segments = mutableListOf<Segment>()
            val arcs = mutableListOf<TagArc>()
            var cumulative = 0L
            for (tag in ordered) {
                val members = sortedSegments(allocationsByTag[tag.id].orEmpty(), spendingByTag[tag.id].orEmpty(), tag.id)
                val start = cumulative
                segments += members
                cumulative += members.sumOf { it.amount }
                arcs += TagArc(
                    tag = tag,
                    bucket = bucket(allocationsByTag[tag.id].orEmpty(), spendingByTag[tag.id].orEmpty(), totalBudget),
                    memberSegmentIds = members.map { it.id }.toSet(),
                    startFraction = if (total > 0) start.toDouble() / total else 0.0,
                    endFraction = if (total > 0) cumulative.toDouble() / total else 0.0,
                )
            }
            segments += sortedSegments(untaggedAllocations, untaggedSpending, null)
            if (headroom > 0) segments += Segment("headroom", Kind.Headroom, headroom, null)
            // No "Untagged" chip when nothing is tagged: one chip covering everything is noise.
            val untagged = if (arcs.isEmpty() || (untaggedAllocations.isEmpty() && untaggedSpending.isEmpty())) null
            else bucket(untaggedAllocations, untaggedSpending, totalBudget)
            return AllocationTagBreakdown(segments, arcs, untagged, headroom, total, totalBudget)
        }

        private fun sortedSegments(allocations: List<BudgetAllocation>, spending: List<UnallocatedSpending>, tagId: String?): List<Segment> =
            allocations.sortedWith(compareByDescending<BudgetAllocation> { it.allocated }.thenBy { it.category.key })
                .map { Segment("alloc-${it.category.key}", Kind.Allocated(it.category), it.allocated, tagId) } +
                spending.sortedWith(compareByDescending<UnallocatedSpending> { it.spent }.thenBy { it.category.key })
                    .map { Segment("offplan-${it.category.key}", Kind.OffPlan(it.category), it.spent, tagId) }

        private fun bucket(allocations: List<BudgetAllocation>, spending: List<UnallocatedSpending>, totalBudget: Long): Bucket {
            val allocated = allocations.sumOf { it.allocated }
            val offPlan = spending.sumOf { it.spent }
            return Bucket(
                allocated = allocated,
                used = allocations.sumOf { it.used } + offPlan,
                offPlan = offPlan,
                share = if (totalBudget > 0) allocated.toDouble() / totalBudget else 0.0,
            )
        }
    }
}
