package com.arthurrios.finova.domain.coachmarks

import com.arthurrios.finova.domain.coachmarks.CoachMarkRunMode.Automatic
import com.arthurrios.finova.domain.coachmarks.CoachMarkRunMode.Replay
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget as Target
import com.arthurrios.finova.ui.coachmarks.CoachMarkStrings
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoachMarkGuidesTest {
    private val nothing = CoachMarkFacts()
    private val withBudget = CoachMarkFacts(hasAnyBudget = true)
    private val everything = CoachMarkFacts(
        hasAnyBudget = true, hasBudgetThisMonth = true, hasAnyAllocation = true, hasAllocationThisMonth = true,
        hasRecurringTransaction = true, hasAnyTransaction = true, hasCreditCard = true,
    )
    private val saveEvents = listOf(
        CoachMarkEvent.BudgetSaved, CoachMarkEvent.AllocationSaved, CoachMarkEvent.TransactionSaved, CoachMarkEvent.CreditCardSaved,
    )

    private fun steps(guide: CoachMarkGuideId, facts: CoachMarkFacts = nothing, mode: CoachMarkRunMode = Replay) =
        CoachMarkGuides.steps(guide, facts, mode)

    private fun ids(guide: CoachMarkGuideId, facts: CoachMarkFacts = nothing) = steps(guide, facts).map { it.id }

    private fun writesData(step: CoachMarkStep) =
        saveEvents.any { step.kind == CoachMarkStepKind.Action(CoachMarkAdvance.Event(it)) }

    private fun session(guide: CoachMarkGuideId, facts: CoachMarkFacts = nothing) =
        CoachMarkSession(guide, Replay, steps(guide, facts))

    private fun CoachMarkSession.at(id: String): CoachMarkSession {
        var session = this
        while (session.step.id != id) session = session.advanced()!!
        return session
    }

    // Replay -----------------------------------------------------------------------------------

    @Test fun withExistingDataAGuideShowsNotesOnlyAndNeverOpensAForm() {
        CoachMarkGuideId.entries.forEach { guide ->
            val list = steps(guide, everything)
            assertFalse("$guide asks to save", list.any(::writesData))
            assertFalse("$guide opens a form", list.any { it.returnTo != null })
            assertTrue(list.isNotEmpty())
        }
    }

    @Test fun replayOnANewUserAsksForTheRealAction() {
        assertTrue(steps(CoachMarkGuideId.FirstBudget).any(::writesData))
    }

    @Test fun allSetCardOnlyEndsTheAutomaticChain() {
        assertNull(CoachMarkGuides.steps(CoachMarkGuideId.Allocations, nothing, Automatic).last().target)
        assertNotNull(CoachMarkGuides.steps(CoachMarkGuideId.Allocations, nothing, Replay).last().target)
    }

    // Step lists -------------------------------------------------------------------------------

    @Test fun salaryGuideWalksEveryFieldThenTheSave() {
        assertEquals(
            listOf("monthFace", "add", "mode", "title", "category", "amount", "date", "dateRule", "type", "save", "note"),
            ids(CoachMarkGuideId.SalaryAndExpenses),
        )
    }

    @Test fun transactionGuideWalksEveryField() {
        assertEquals(
            listOf("monthFace", "add", "title", "category", "amount", "date", "dateRule", "type", "save", "note"),
            ids(CoachMarkGuideId.FirstTransaction),
        )
    }

    @Test fun categoryAndCardFormsWalkEveryField() {
        assertEquals(
            listOf("budgetFace", "add", "category", "amount", "recurring", "save", "note"),
            ids(CoachMarkGuideId.Allocations, withBudget),
        )
        assertEquals(
            listOf("avatar", "row", "add", "name", "lastFour", "brand", "closingDay", "dueDay", "limit", "save", "note"),
            ids(CoachMarkGuideId.CreditCard),
        )
    }

    @Test fun budgetGuide() {
        assertEquals(listOf("define", "form", "back"), ids(CoachMarkGuideId.FirstBudget))
        assertEquals(
            listOf("existingCard", "existingConfig", "existingForm", "existingList", "back"),
            ids(CoachMarkGuideId.FirstBudget, everything),
        )
    }

    @Test fun budgetFormNamesTheSuggestionOnlyWhenThereIsIncome() {
        fun key(facts: CoachMarkFacts) = steps(CoachMarkGuideId.FirstBudget, facts).first { it.target == Target.BudgetsForm }.textKey
        assertEquals("coachMarks.firstBudget.form", key(nothing))
        assertEquals("coachMarks.firstBudget.formWithIncome", key(CoachMarkFacts(hasIncomeThisMonth = true)))
    }

    @Test fun budgetHistoryGuideHasEightStepsAndNoNoteHoldsItUp() {
        val list = steps(CoachMarkGuideId.BudgetHistory)
        assertEquals(listOf("open", "chart", "filter", "range", "savings", "projected", "projectedCard", "note"), list.map { it.id })
        assertTrue(list.drop(1).dropLast(1).all { it.skipsWhenAbsent })
        assertNull(list.last().target)
    }

    @Test fun tourCoversTheDashboard() {
        assertEquals(
            listOf("monthFace", "months", "card", "budgetToggle", "monthFace", "transactions", "add", "notifications", "avatar"),
            ids(CoachMarkGuideId.DashboardTour),
        )
    }

    @Test fun repeatStepWaitsForNextSoItsOptionsStayInView() {
        assertNull(steps(CoachMarkGuideId.Allocations, withBudget).first { it.id == "recurring" }.triedBy)
    }

    @Test fun everyFormStepIsOnItsOwnField() {
        val wholeForms = listOf(Target.AllocationSheet, Target.TransactionSheet, Target.AddCardForm)
        CoachMarkGuideId.entries.forEach { guide ->
            steps(guide, withBudget).filter { it.returnTo != null }.forEach { step ->
                assertFalse(step.id, step.target == null || step.target in wholeForms)
            }
        }
    }

    @Test fun onlyFormStepsOwnTheKeyboard() {
        CoachMarkGuideId.entries.forEach { guide ->
            steps(guide, mode = Automatic).filter { it.ownsKeyboard }.forEach { step ->
                assertTrue("$guide.${step.id}", writesData(step) || step.returnTo != null)
            }
        }
    }

    // Moving through a session -----------------------------------------------------------------

    @Test fun everySaveStepAdvancesOnlyOnItsEvent() {
        val form = session(CoachMarkGuideId.FirstBudget).advanced()!!
        assertEquals("form", form.step.id)
        assertFalse(form.isSatisfied(by = CoachMarkEvent.TransactionSaved))
        assertTrue(form.isSatisfied(by = CoachMarkEvent.BudgetSaved))
    }

    @Test fun fillingAFieldMovesItsStepOnButOnlyASaveEndsTheForm() {
        val base = session(CoachMarkGuideId.FirstTransaction)
        val title = base.at("title")
        assertTrue(title.isTried(by = CoachMarkEvent.FieldFilled(Target.TransactionTitle)))
        assertFalse(title.isTried(by = CoachMarkEvent.FieldFilled(Target.TransactionAmount)))
        val save = base.at("save")
        assertTrue(save.step.isAction)
        assertTrue(save.isSatisfied(by = CoachMarkEvent.TransactionSaved))
    }

    @Test fun closingASheetUnsavedReturnsToTheButtonThatOpenedIt() {
        val field = session(CoachMarkGuideId.Allocations, withBudget).at("category")
        assertEquals("add", field.wentBack(field.step.returnTo!!).step.id)
    }

    @Test fun advancingPastTheLastStepFinishes() {
        var session = session(CoachMarkGuideId.BudgetHistory)
        while (!session.isLastStep) session = session.advanced()!!
        assertNull(session.advanced())
    }

    @Test fun counterLeavesOutStepsThatWereSkipped() {
        val total = steps(CoachMarkGuideId.DashboardTour).size
        val skipped = session(CoachMarkGuideId.DashboardTour).skipped()!!
        assertEquals(1, skipped.shownPosition)
        assertEquals(total - 1, skipped.shownTotal)
        assertEquals(2, skipped.advanced()!!.shownPosition)
    }

    @Test fun tourNotesMoveOnWhenTheUserTriesThem() {
        val months = session(CoachMarkGuideId.DashboardTour).skipped()!!
        assertEquals("months", months.step.id)
        assertTrue(months.isTried(by = CoachMarkEvent.DashboardMonthChanged))
        assertFalse(months.isTried(by = CoachMarkEvent.DashboardDayChanged))
        assertFalse(months.isSatisfied(by = CoachMarkEvent.DashboardMonthChanged))
    }

    // Text -------------------------------------------------------------------------------------

    private val allFacts = listOf(nothing, CoachMarkFacts(hasIncomeThisMonth = true), withBudget, everything)

    private fun allStepKeys() = CoachMarkGuideId.entries.flatMap { guide ->
        allFacts.flatMap { facts ->
            CoachMarkRunMode.entries.flatMap { mode -> CoachMarkGuides.steps(guide, facts, mode).map { it.textKey } }
        }
    }.toSet()

    private fun strings(folder: String): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File("src/main/res/$folder/strings.xml"))
        val nodes = document.getElementsByTagName("string")
        return (0 until nodes.length).associate { index ->
            val node = nodes.item(index)
            node.attributes.getNamedItem("name").nodeValue to node.textContent
        }
    }

    private fun resourceName(key: String) =
        Regex("([a-z0-9])([A-Z])").replace(key) { "${it.groupValues[1]}_${it.groupValues[2].lowercase()}" }.replace('.', '_').lowercase()

    @Test fun everyStepHasTextInBothLanguages() {
        val keys = allStepKeys() + CoachMarkGuideId.entries.flatMap { listOf(it.titleKey, it.subtitleKey) } +
            listOf("next", "done", "skip", "skipAll", "close").map { "coachMarks.button.$it" }
        keys.forEach { key -> assertNotNull(key, CoachMarkStrings.resource(key)) }
        listOf("values", "values-pt-rBR").forEach { folder ->
            val strings = strings(folder)
            keys.forEach { key -> assertNotNull("$folder: $key", strings[resourceName(key)]) }
        }
    }

    @Test fun noGuideMentionsWhatThisVersionDoesNotHave() {
        val forbidden = listOf("sync", "family", "famíl", "group", "grupo", "import", "icloud")
        listOf("values", "values-pt-rBR").forEach { folder ->
            val strings = strings(folder)
            allStepKeys().forEach { key ->
                val text = strings.getValue(resourceName(key)).lowercase()
                forbidden.forEach { word -> assertFalse("$key says $word", word in text) }
            }
        }
    }

    @Test fun theDateRuleMentionsWeekendsAndNotHolidays() {
        listOf("values", "values-pt-rBR").forEach { folder ->
            val text = strings(folder).getValue("coach_marks_first_transaction_date_rule").lowercase()
            assertFalse(text, "holiday" in text || "feriado" in text)
        }
    }
}
