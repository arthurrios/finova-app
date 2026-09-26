package com.arthurrios.finova.domain.tags

import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.UnallocatedSpending
import com.arthurrios.finova.domain.model.TransactionCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.YearMonth

class AllocationTagsTest {
    private val month = YearMonth.of(2026, 9)
    private fun alloc(category: TransactionCategory, amount: Long, used: Long = 0) =
        BudgetAllocation(id = amount, month = month, category = category, allocated = amount, isRecurring = false, parentId = null, used = used)

    private fun book(vararg tags: Pair<AllocationTag, List<TransactionCategory>>) = AllocationTagBook(
        tags = tags.map { it.first },
        categoryTagIds = tags.flatMap { (tag, cats) -> cats.map { it.key to tag.id } }.toMap(),
    )

    @Test fun newTagsTakeColoursInAssignmentOrderAndReuseFreedOnes() {
        var b = AllocationTagBook()
        val colours = (1..3).map { b.creating("T$it")!!.also { (next, _) -> b = next }.second.colorIndex }
        assertEquals(listOf(5, 2, 3), colours)
        b = b.deleting(b.orderedTags[1].id)
        assertEquals(2, b.creating("again")!!.second.colorIndex)
    }

    @Test fun blankNamesAreRefused() {
        assertNull(AllocationTagBook().creating("   "))
    }

    @Test fun assigningMovesACategoryAndDeletingDropsItsLinks() {
        val (b1, essentials) = AllocationTagBook().creating("Essentials")!!
        val (b2, fun_) = b1.creating("Fun")!!
        val b3 = b2.assigning(TransactionCategory.Market, essentials.id).assigning(TransactionCategory.Market, fun_.id)
        assertEquals(fun_.id, b3.tagFor(TransactionCategory.Market)?.id)
        assertTrue(b3.deleting(fun_.id).categoryTagIds.isEmpty())
    }

    @Test fun sanitizeDropsLinksToMissingTagsAndDensifiesOrder() {
        val tag = AllocationTag(id = "a", name = " Home ", colorIndex = 11, sortOrder = 7)
        val dirty = AllocationTagBook(listOf(tag, tag.copy(name = "dup")), mapOf("market" to "a", "meals" to "gone"))
        val clean = dirty.sanitized()
        assertEquals(1, clean.tags.size)
        assertEquals("Home", clean.tags[0].name)
        assertEquals(0, clean.tags[0].sortOrder)
        assertEquals(3, clean.tags[0].colorIndex)
        assertFalse("meals" in clean.categoryTagIds)
    }

    @Test fun reorderingFollowsTheGivenIds() {
        val b = AllocationTagBook(listOf(
            AllocationTag(id = "a", name = "A", colorIndex = 0, sortOrder = 0),
            AllocationTag(id = "b", name = "B", colorIndex = 1, sortOrder = 1),
            AllocationTag(id = "c", name = "C", colorIndex = 2, sortOrder = 2),
        ))
        assertEquals(listOf("c", "a", "b"), b.reordering(listOf("c", "a")).orderedTags.map { it.id })
    }

    @Test fun withoutTagsTheOrderIsAllocationsThenOffPlanThenHeadroom() {
        val breakdown = AllocationTagBreakdown.of(
            allocations = listOf(alloc(TransactionCategory.Market, 100), alloc(TransactionCategory.Meals, 300)),
            unallocatedSpending = listOf(UnallocatedSpending(TransactionCategory.Gifts, 50)),
            unallocatedHeadroom = 200, totalBudget = 600, book = AllocationTagBook(),
        )
        assertEquals(listOf("alloc-meals", "alloc-market", "offplan-gifts", "headroom"), breakdown.segments.map { it.id })
        assertFalse(breakdown.hasTags)
        assertNull(breakdown.untagged)
    }

    @Test fun taggedSlicesComeFirstInTagOrderWithContiguousArcs() {
        val a = AllocationTag(id = "a", name = "A", colorIndex = 0, sortOrder = 1)
        val b = AllocationTag(id = "b", name = "B", colorIndex = 1, sortOrder = 0)
        val breakdown = AllocationTagBreakdown.of(
            allocations = listOf(alloc(TransactionCategory.Market, 100, used = 40), alloc(TransactionCategory.Meals, 300), alloc(TransactionCategory.Gifts, 200)),
            unallocatedSpending = listOf(UnallocatedSpending(TransactionCategory.Entertainment, 100)),
            unallocatedHeadroom = 300, totalBudget = 1_000,
            book = book(a to listOf(TransactionCategory.Market, TransactionCategory.Entertainment), b to listOf(TransactionCategory.Gifts)),
        )
        assertEquals(listOf("alloc-gifts", "alloc-market", "offplan-entertainment", "alloc-meals", "headroom"), breakdown.segments.map { it.id })
        assertEquals(listOf("b", "a"), breakdown.tagArcs.map { it.tag.id })
        val total = 1_000.0
        assertEquals(0.0, breakdown.tagArcs[0].startFraction, 1e-9)
        assertEquals(200 / total, breakdown.tagArcs[0].endFraction, 1e-9)
        assertEquals(400 / total, breakdown.tagArcs[1].endFraction, 1e-9)
        val bucketA = breakdown.tagArcs[1].bucket
        assertEquals(100L, bucketA.allocated)
        assertEquals(140L, bucketA.used)
        assertEquals(0.1, bucketA.share, 1e-9)
        assertEquals(300L, breakdown.untagged?.allocated)
        assertTrue(breakdown.segmentBelongsTo("offplan-entertainment", "a"))
    }

    @Test fun aTagWithNoMoneyThisMonthGetsNoArc() {
        val a = AllocationTag(id = "a", name = "A", colorIndex = 0, sortOrder = 0)
        val breakdown = AllocationTagBreakdown.of(
            allocations = listOf(alloc(TransactionCategory.Market, 100)), unallocatedSpending = emptyList(),
            unallocatedHeadroom = 0, totalBudget = 100, book = book(a to listOf(TransactionCategory.Meals)),
        )
        assertFalse(breakdown.hasTags)
    }
}
