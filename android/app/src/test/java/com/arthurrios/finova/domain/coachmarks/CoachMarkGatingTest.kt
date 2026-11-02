package com.arthurrios.finova.domain.coachmarks

import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId.Allocations
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId.FirstBudget
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId.SalaryAndExpenses
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The promises the guides make: a new user is guided, an existing user is never interrupted. */
class CoachMarkGatingTest {
    private val empty = CoachMarkFacts()
    private val enrolled = CoachMarkGating.enrolling(CoachMarkState(), empty)

    private class MemoryPreferences : CoachMarkPreferences {
        val values = mutableMapOf<String, String>()
        override fun getString(key: String) = values[key]
        override fun putString(key: String, value: String) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }

    private val preferences = MemoryPreferences()
    private val store = CoachMarkStateStore(preferences)

    private fun next(state: CoachMarkState, facts: CoachMarkFacts = empty) = CoachMarkGating.nextAutomaticGuide(state, facts)

    @Test fun newUserIsEnrolledAndStartsWithSalary() {
        assertEquals(true, enrolled.isEnrolled)
        assertEquals(SalaryAndExpenses, next(enrolled))
    }

    @Test fun chainLeadsFromSalaryToBudgetToAllocationsThenEnds() {
        var facts = CoachMarkFacts(hasRecurringTransaction = true, hasAnyTransaction = true)
        assertEquals(FirstBudget, next(enrolled, facts))
        facts = facts.copy(hasAnyBudget = true)
        assertEquals(Allocations, next(enrolled, facts))
        facts = facts.copy(hasAnyAllocation = true)
        assertNull(next(enrolled, facts))
    }

    @Test fun savingTheFirstBudgetDoesNotEndTheUsersOwnChain() {
        val after = CoachMarkGating.enrolling(enrolled, CoachMarkFacts(hasAnyBudget = true))
        assertEquals(true, after.isEnrolled)
    }

    @Test fun aUserWithABudgetButNoIncomeStillGetsTheSalaryGuide() {
        val state = enrolled.copy(completed = setOf(FirstBudget))
        assertEquals(SalaryAndExpenses, next(state, CoachMarkFacts(hasAnyBudget = true, hasBudgetThisMonth = true)))
    }

    @Test fun skippingSalaryStillOffersTheBudgetWithNoSuggestionText() {
        val state = enrolled.copy(skipped = setOf(SalaryAndExpenses))
        assertEquals(FirstBudget, next(state))
        val form = CoachMarkGuides.steps(FirstBudget, empty, CoachMarkRunMode.Automatic)
            .first { it.target == CoachMarkTarget.BudgetsForm }
        assertEquals("coachMarks.firstBudget.form", form.textKey)
    }

    @Test fun allocationsGuideWaitsForABudget() {
        assertNull(next(enrolled.copy(skipped = setOf(SalaryAndExpenses, FirstBudget))))
    }

    @Test fun existingUserIsNeverEnrolled() {
        listOf(
            CoachMarkFacts(hasAnyBudget = true),
            CoachMarkFacts(hasAnyAllocation = true),
            CoachMarkFacts(hasAnyTransaction = true),
            CoachMarkFacts(hasCreditCard = true),
        ).forEach { facts ->
            val state = CoachMarkGating.enrolling(CoachMarkState(), facts)
            assertEquals(false, state.isEnrolled)
            assertTrue(CoachMarkGating.isPermanentlyQuiet(state))
            assertNull(next(state, facts))
        }
    }

    @Test fun existingUserStaysQuietEvenIfTheirDataGoesAway() {
        val state = CoachMarkGating.enrolling(CoachMarkState(), CoachMarkFacts(hasAnyTransaction = true))
        val later = CoachMarkGating.enrolling(state, empty)
        assertEquals(false, later.isEnrolled)
        assertNull(next(later))
    }

    @Test fun newMonthWithoutABudgetDoesNotRestartTheGuide() {
        val lastMonths = CoachMarkFacts(hasAnyBudget = true, hasBudgetThisMonth = false)
        assertTrue(CoachMarkGating.isSetupDone(FirstBudget, lastMonths))
        assertNull(next(enrolled.copy(completed = setOf(SalaryAndExpenses, Allocations)), lastMonths))
    }

    @Test fun reinstallWithDataStartsNoGuide() {
        val facts = CoachMarkFacts(hasAnyBudget = true, hasAnyTransaction = true)
        store.clear("user")
        assertNull(next(CoachMarkGating.enrolling(store.load("user"), facts), facts))
    }

    @Test fun losingDataDoesNotRestartACompletedGuide() {
        assertEquals(FirstBudget, next(enrolled.copy(completed = setOf(SalaryAndExpenses))))
    }

    @Test fun skipAllStopsEveryAutomaticGuide() {
        val state = enrolled.copy(isAutoDisabled = true)
        assertTrue(CoachMarkGating.isPermanentlyQuiet(state))
        assertNull(next(state))
    }

    @Test fun skipEndsOneGuideAndTheChainGoesOn() {
        assertEquals(FirstBudget, next(enrolled.copy(skipped = setOf(SalaryAndExpenses))))
    }

    @Test fun aGuideTheUserKeepsLeavingStopsOffering() {
        val below = enrolled.copy(autoStarts = mapOf(SalaryAndExpenses to CoachMarkGating.MAX_AUTO_STARTS - 1))
        assertEquals(SalaryAndExpenses, next(below))
        val atLimit = enrolled.copy(autoStarts = mapOf(SalaryAndExpenses to CoachMarkGating.MAX_AUTO_STARTS))
        assertNotEquals(SalaryAndExpenses, next(atLimit))
    }

    @Test fun onlyTheSetupChainIsAutomatic() {
        assertEquals(listOf(SalaryAndExpenses, FirstBudget, Allocations), CoachMarkGuideId.automaticChain)
    }

    @Test fun thereAreSevenGuides() {
        assertEquals(7, CoachMarkGuideId.entries.size)
    }

    // Per-user state --------------------------------------------------------------------------

    @Test fun stateIsPerUser() {
        val first = CoachMarkState(isEnrolled = true, isAutoDisabled = true, completed = setOf(FirstBudget))
        store.save(first, "first")
        assertEquals(first, store.load("first"))
        assertEquals(CoachMarkState(), store.load("second"))
    }

    @Test fun everyFieldSurvivesLogOutAndBackIn() {
        val state = enrolled.copy(
            completed = setOf(FirstBudget), skipped = setOf(Allocations),
            autoStarts = mapOf(FirstBudget to 1, Allocations to 3),
            reminderDismissals = 2, reminderDismissedAtMillis = 1_234_567L,
        )
        store.save(state, "user")
        assertEquals(state, CoachMarkStateStore(preferences).load("user"))
    }

    @Test fun anUnansweredEnrollmentStaysUnanswered() {
        store.save(CoachMarkState(), "user")
        assertNull(store.load("user").isEnrolled)
    }

    @Test fun corruptStateIsABlankState() {
        preferences.values["coachMarks.state.user"] = "nonsense"
        assertEquals(CoachMarkState(), store.load("user"))
        preferences.values["coachMarks.state.user"] = "enrolled=maybe\nautoStarts=firstBudget:x,other:1\nreminderDismissals=z"
        assertEquals(CoachMarkState(), store.load("user"))
    }

    // Reminder --------------------------------------------------------------------------------

    private val unfinished = CoachMarkState(isEnrolled = true, isAutoDisabled = true)
    private val time = 1_000_000_000L

    private fun reminder(state: CoachMarkState, facts: CoachMarkFacts = empty, now: Long = time) =
        CoachMarkGating.reminderGuide(state, facts, now)

    @Test fun reminderNamesTheFirstSetupLeft() {
        assertEquals(CoachMarkGuideId.automaticChain.first(), reminder(unfinished))
    }

    @Test fun reminderNeverReachesAnExistingUser() {
        assertNull(reminder(unfinished.copy(isEnrolled = false)))
    }

    @Test fun reminderWaitsWhileAGuideWouldStartByItself() {
        assertNull(reminder(unfinished.copy(isAutoDisabled = false)))
    }

    @Test fun reminderShowsAfterSkipAll() {
        assertNotNull(reminder(enrolled.copy(isAutoDisabled = true)))
    }

    @Test fun reminderStaysAwayAfterClosingThenReturns() {
        val state = unfinished.copy(reminderDismissals = 1, reminderDismissedAtMillis = time)
        assertNull(reminder(state, now = time + CoachMarkGating.REMINDER_PAUSE_MILLIS - 1))
        assertNotNull(reminder(state, now = time + CoachMarkGating.REMINDER_PAUSE_MILLIS))
    }

    @Test fun reminderPauseIsThreeDays() {
        assertEquals(3 * 86_400_000L, CoachMarkGating.REMINDER_PAUSE_MILLIS)
    }

    @Test fun reminderStopsAfterThreeCloses() {
        assertNull(reminder(unfinished.copy(reminderDismissals = CoachMarkGating.MAX_REMINDER_DISMISSALS)))
        assertFalse(CoachMarkGating.MAX_REMINDER_DISMISSALS != 3)
    }

    @Test fun reminderEndsWhenEverySetupIsDone() {
        val done = CoachMarkFacts(hasAnyBudget = true, hasAnyAllocation = true, hasRecurringTransaction = true, hasAnyTransaction = true, hasCreditCard = true)
        assertNull(reminder(unfinished, done))
    }

    @Test fun reminderLeavesOutACompletedGuideAndAllocationsWithNoBudget() {
        assertEquals(FirstBudget, reminder(unfinished.copy(completed = setOf(SalaryAndExpenses))))
        assertNull(reminder(unfinished.copy(completed = setOf(SalaryAndExpenses, FirstBudget))))
    }
}
