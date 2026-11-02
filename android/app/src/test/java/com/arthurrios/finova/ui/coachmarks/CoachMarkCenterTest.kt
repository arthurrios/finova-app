package com.arthurrios.finova.ui.coachmarks

import com.arthurrios.finova.domain.coachmarks.CoachMarkEvent
import com.arthurrios.finova.domain.coachmarks.CoachMarkFacts
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuides
import com.arthurrios.finova.domain.coachmarks.CoachMarkPreferences
import com.arthurrios.finova.domain.coachmarks.CoachMarkRunMode
import com.arthurrios.finova.domain.coachmarks.CoachMarkSession
import com.arthurrios.finova.domain.coachmarks.CoachMarkState
import com.arthurrios.finova.domain.coachmarks.CoachMarkStateStore
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget
import com.arthurrios.finova.ui.coachmarks.CoachMarkCenter.Companion.missingTargetResponse
import com.arthurrios.finova.ui.coachmarks.CoachMarkCenter.Companion.screenChange
import com.arthurrios.finova.ui.coachmarks.CoachMarkCenter.Ending
import com.arthurrios.finova.ui.coachmarks.CoachMarkCenter.MissingTargetResponse
import com.arthurrios.finova.ui.coachmarks.CoachMarkCenter.ScreenChange
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoachMarkCenterTest {
    private fun steps(guide: CoachMarkGuideId, facts: CoachMarkFacts = CoachMarkFacts()) =
        CoachMarkGuides.steps(guide, facts, CoachMarkRunMode.Replay)

    private fun card() = steps(CoachMarkGuideId.CreditCard)
    private fun tour() = steps(CoachMarkGuideId.DashboardTour)

    // Missing targets --------------------------------------------------------------------------

    @Test fun anOptionalNoteStaysUpForAsLongAsItsTargetIsMissing() {
        val note = card().last()
        assertTrue(note.isTargetOptional)
        // Any other answer here hides a card that the next tick brings back: the flicker.
        listOf(0L, 600L, 5_000L, 60_000L).forEach { lost ->
            assertEquals(MissingTargetResponse.Show, missingTargetResponse(note, true, lost, lost + 3_000))
        }
    }

    @Test fun anOptionalNoteWaitsThenShowsWithoutGoingThroughHidden() {
        val note = card().last()
        fun response(waited: Long) = missingTargetResponse(note, false, 0, waited)
        assertEquals(MissingTargetResponse.Wait, response(100))
        assertEquals(MissingTargetResponse.StepAside, response(1_000))
        assertEquals(MissingTargetResponse.Show, response(3_000))
        assertEquals(MissingTargetResponse.Show, response(30_000))
    }

    @Test fun stepsThatNeedTheirTargetStillGiveUpOnIt() {
        val form = card().first { it.target == CoachMarkTarget.AddCardSave }
        val required = tour().first { it.target == CoachMarkTarget.DashboardMonthCard }
        assertEquals(MissingTargetResponse.Wait, missingTargetResponse(form, true, 100, 1_000))
        assertEquals(MissingTargetResponse.StepAside, missingTargetResponse(form, true, 1_000, 1_000))
        assertEquals(MissingTargetResponse.Abandon, missingTargetResponse(form, false, 0, 8_000))
        assertEquals(MissingTargetResponse.StepAside, missingTargetResponse(required, true, 1_000, 1_000))
        assertEquals(MissingTargetResponse.Skip, missingTargetResponse(required, false, 0, 3_000))
    }

    @Test fun aStepWithNoTargetOnThisScreenPassesAtOnce() {
        val range = steps(CoachMarkGuideId.BudgetHistory).first { it.id == "range" }
        assertEquals(MissingTargetResponse.Skip, missingTargetResponse(range, false, 0, 500))
    }

    // Recording --------------------------------------------------------------------------------

    private fun history(mode: CoachMarkRunMode) = CoachMarkSession(CoachMarkGuideId.BudgetHistory, mode, steps(CoachMarkGuideId.BudgetHistory))

    @Test fun finishingAGuideIsRememberedHoweverItStarted() {
        CoachMarkRunMode.entries.forEach { mode ->
            val state = CoachMarkCenter.recording(Ending.Completed, history(mode), CoachMarkState())
            assertTrue(CoachMarkGuideId.BudgetHistory in state.completed)
        }
    }

    @Test fun leavingAReplayEarlyRecordsNothing() {
        listOf(Ending.Skipped, Ending.SkippedAll, Ending.Abandoned).forEach { ending ->
            assertEquals(CoachMarkState(), CoachMarkCenter.recording(ending, history(CoachMarkRunMode.Replay), CoachMarkState()))
        }
    }

    @Test fun automaticSkipsAreRememberedAndBeingCutOffIsNot() {
        val session = history(CoachMarkRunMode.Automatic)
        assertTrue(CoachMarkGuideId.BudgetHistory in CoachMarkCenter.recording(Ending.Skipped, session, CoachMarkState()).skipped)
        assertTrue(CoachMarkCenter.recording(Ending.SkippedAll, session, CoachMarkState()).isAutoDisabled)
        assertEquals(CoachMarkState(), CoachMarkCenter.recording(Ending.Abandoned, session, CoachMarkState()))
    }

    // Screen changes ---------------------------------------------------------------------------

    @Test fun aNoteWaitsWhileItsTargetOpensAnotherScreen() {
        val note = tour().first { it.id == "add" }
        val (home, sheet) = Any() to Any()
        fun change(top: Any, left: Boolean) = screenChange(note, home, top, left)
        assertEquals(ScreenChange.Same, change(home, false))
        assertEquals(ScreenChange.Left, change(sheet, false))
        assertEquals(ScreenChange.Left, change(sheet, true))
        assertEquals(ScreenChange.CameBack, change(home, true))
    }

    @Test fun anActionStepDoesNotTreatItsOwnScreenChangeAsTrying() {
        val action = steps(CoachMarkGuideId.FirstBudget).first()
        assertEquals(ScreenChange.Same, screenChange(action, Any(), Any(), false))
    }

    @Test fun aFormStepTreatsTheSheetClosingAsLostNotAsTrying() {
        val field = steps(CoachMarkGuideId.SalaryAndExpenses).first { it.id == "title" }
        assertEquals("add", field.returnTo)
        assertEquals(ScreenChange.Same, screenChange(field, Any(), Any(), false))
        assertEquals(MissingTargetResponse.StepAside, missingTargetResponse(field, true, 1_000, 1_000))
    }

    // Card content -----------------------------------------------------------------------------

    @Test fun captionAndButtonsDifferBetweenAutomaticAndReplay() {
        val list = tour()
        assertNotNull(CoachMarkCenter.content(CoachMarkSession(CoachMarkGuideId.DashboardTour, CoachMarkRunMode.Automatic, list)).skipAllKey)
        val replay = CoachMarkCenter.content(CoachMarkSession(CoachMarkGuideId.DashboardTour, CoachMarkRunMode.Replay, list))
        assertNull(replay.skipAllKey)
        assertEquals("coachMarks.button.close", replay.skipKey)
    }

    @Test fun anActionStepHasNoNextAndTheLastNoteHasOnlyDone() {
        val action = CoachMarkCenter.content(CoachMarkSession(CoachMarkGuideId.FirstBudget, CoachMarkRunMode.Automatic, steps(CoachMarkGuideId.FirstBudget)))
        assertNull(action.nextKey)
        val list = tour()
        val last = CoachMarkCenter.content(CoachMarkSession(CoachMarkGuideId.DashboardTour, CoachMarkRunMode.Automatic, list, index = list.lastIndex))
        assertEquals("coachMarks.button.done", last.nextKey)
        assertNull(last.skipKey)
        assertNull(last.skipAllKey)
    }

    // The engine, against a stage made of plain values -----------------------------------------

    private class Memory : CoachMarkPreferences {
        val values = mutableMapOf<String, String>()
        override fun getString(key: String) = values[key]
        override fun putString(key: String, value: String) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }

    private class FakeStage : CoachMarkStage {
        val dashboard = Any()
        val visible = mutableMapOf<CoachMarkTarget, MarkRect>()
        val scrolled = mutableListOf<CoachMarkTarget>()
        val filled = mutableSetOf<CoachMarkTarget>()
        override fun isFilled(target: CoachMarkTarget) = target in filled
        var top: Any = dashboard
        var route: String? = "dashboard"
        override var isAppActive = true
        override val topScreen get() = top
        override val topRoute get() = route
        override val isDashboardOnTop get() = top === dashboard
        override var keyboardTop: Float? = null
        override var isLoadingScreen = false
        override val overlayHost get() = top
        override fun find(target: CoachMarkTarget) = visible[target]
        override fun scrollIntoView(target: CoachMarkTarget) { scrolled += target }
        override fun prepareDashboardForGuide() = Unit
    }

    private val rect = MarkRect(10f, 10f, 60f, 60f)

    private inner class Rig(facts: CoachMarkFacts = CoachMarkFacts()) {
        var time = 1_000L
        val stage = FakeStage()
        val store = CoachMarkStateStore(Memory())
        val center = CoachMarkCenter(store, { facts }, { "user" }, CoroutineScope(Dispatchers.Unconfined), { time }).also { it.stage = stage }

        /** Enough ticks to pass the settle, land a mark and note which screen it landed on. */
        fun land() = repeat(4) { step(100) }

        fun step(millis: Long) {
            time += millis
            center.tick()
        }

        val stepId get() = center.session.value?.step?.id

        fun replay(guide: CoachMarkGuideId) = center.startReplay(guide)
    }

    @Test fun eventsWithNoGuideRunningDoNothing() {
        val rig = Rig()
        rig.center.post(CoachMarkEvent.BudgetSaved)
        assertNull(rig.center.session.value)
    }

    @Test fun aNewUserStartsTheChainAndAnExistingUserDoesNot() = runBlocking {
        val fresh = Rig()
        fresh.center.startAutomaticGuideIfDue()
        assertEquals(CoachMarkGuideId.SalaryAndExpenses, fresh.center.session.value?.guide)
        assertEquals(1, fresh.store.load("user").autoStarts[CoachMarkGuideId.SalaryAndExpenses])

        val existing = Rig(CoachMarkFacts(hasAnyTransaction = true))
        existing.center.startAutomaticGuideIfDue()
        assertNull(existing.center.session.value)
        assertEquals(false, existing.store.load("user").isEnrolled)
    }

    @Test fun noGuideStartsWhileAnotherActivityIsUp() = runBlocking {
        val rig = Rig()
        rig.stage.isAppActive = false
        rig.center.startAutomaticGuideIfDue()
        assertNull(rig.center.session.value)
    }

    @Test fun aStepAlreadySatisfiedPassesWithoutCountingOnTheCard() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.FirstTransaction)
        rig.stage.visible[CoachMarkTarget.DashboardBudgetToggle] = rect
        rig.stage.visible[CoachMarkTarget.DashboardAdd] = rect
        rig.step(0)
        assertEquals("add", rig.stepId)
        assertEquals(1, rig.center.session.value?.shownPosition)
    }

    @Test fun aMarkLandsOnlyOnceTheTargetHoldsStill() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.DashboardTour)
        rig.stage.visible[CoachMarkTarget.DashboardFlipBack] = rect
        rig.step(10)
        assertNull(rig.center.presentation.value)
        rig.stage.visible[CoachMarkTarget.DashboardFlipBack] = rect.offset(0f, 5f)
        rig.step(100)
        assertNull(rig.center.presentation.value)
        rig.step(130)
        assertNotNull(rig.center.presentation.value)
        assertEquals(listOf(CoachMarkTarget.DashboardFlipBack), rig.stage.scrolled)
    }

    @Test fun tryingANoteMovesItOnAfterThePause() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.DashboardTour)
        rig.stage.visible[CoachMarkTarget.DashboardBudgetToggle] = rect
        rig.stage.visible[CoachMarkTarget.DashboardMonthSelector] = rect
        rig.step(0)
        rig.land()
        assertEquals("months", rig.stepId)
        rig.center.post(CoachMarkEvent.DashboardMonthChanged)
        rig.step(CoachMarkCenter.TRIED_PAUSE - 1)
        assertEquals("months", rig.stepId)
        rig.step(1)
        assertEquals("card", rig.stepId)
    }

    @Test fun tryingANoteThatOpensAScreenHidesItAndItMovesOnOnTheWayBack() {
        val rig = Rig(CoachMarkFacts(hasAnyTransaction = true))
        rig.replay(CoachMarkGuideId.FirstTransaction)
        rig.stage.visible[CoachMarkTarget.DashboardBudgetToggle] = rect
        rig.stage.visible[CoachMarkTarget.DashboardAdd] = rect
        rig.step(0)
        rig.center.nextTapped() // "existingList" has no target here; pass it.
        assertEquals("existingAdd", rig.stepId)
        rig.land()
        assertNotNull(rig.center.presentation.value)

        rig.stage.top = Any()
        rig.stage.route = null
        rig.step(33)
        assertNull(rig.center.presentation.value)
        assertEquals("existingAdd", rig.stepId)
        rig.step(60_000)
        assertEquals("existingAdd", rig.stepId)

        rig.stage.top = rig.stage.dashboard
        rig.step(33)
        assertNull(rig.center.session.value)
    }

    @Test fun closingAFormUnfinishedGoesBackToTheStepThatOpenedIt() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.FirstTransaction)
        rig.stage.visible[CoachMarkTarget.DashboardBudgetToggle] = rect
        rig.stage.visible[CoachMarkTarget.TransactionSheet] = rect
        rig.step(0)
        rig.step(0)
        assertEquals("title", rig.stepId)
        rig.stage.visible[CoachMarkTarget.TransactionTitle] = rect
        rig.land()

        // The sheet closes.
        rig.stage.visible.remove(CoachMarkTarget.TransactionTitle)
        rig.stage.visible.remove(CoachMarkTarget.TransactionSheet)
        rig.step(100)
        assertEquals("title", rig.stepId)
        rig.step(500)
        rig.step(100)
        assertEquals("add", rig.stepId)
    }

    @Test fun onlyTheRealSaveEndsAForm() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.FirstBudget)
        rig.stage.visible[CoachMarkTarget.DashboardDefineBudget] = rect
        rig.land()
        rig.stage.visible[CoachMarkTarget.BudgetsForm] = rect
        rig.step(33)
        assertEquals("form", rig.stepId)
        rig.land()
        rig.center.nextTapped()
        assertEquals("form", rig.stepId)
        rig.center.post(CoachMarkEvent.BudgetSaved)
        assertEquals("back", rig.stepId)
    }

    @Test fun aKeyboardThatIsNotTheStepsHidesTheMarkAndAFormsDoesNot() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.DashboardTour)
        rig.stage.visible[CoachMarkTarget.DashboardFlipBack] = rect
        rig.land()
        assertNotNull(rig.center.presentation.value)
        rig.stage.keyboardTop = 500f
        rig.step(33)
        assertNull(rig.center.presentation.value)
        rig.stage.keyboardTop = null
        rig.land()
        assertNotNull(rig.center.presentation.value)
    }

    @Test fun puttingTheKeyboardAwayOnAFilledFieldMovesItsStepOn() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.FirstTransaction)
        rig.stage.visible[CoachMarkTarget.DashboardBudgetToggle] = rect
        rig.stage.visible[CoachMarkTarget.TransactionSheet] = rect
        rig.step(0)
        rig.step(0)
        rig.stage.visible[CoachMarkTarget.TransactionTitle] = rect
        rig.land()
        rig.stage.keyboardTop = 500f
        rig.step(33)

        rig.stage.keyboardTop = null
        rig.step(33)
        rig.step(CoachMarkCenter.TRIED_PAUSE)
        assertEquals("an empty field stays", "title", rig.stepId)

        rig.stage.keyboardTop = 500f
        rig.step(33)
        rig.stage.filled += CoachMarkTarget.TransactionTitle
        rig.stage.keyboardTop = null
        rig.step(33)
        rig.step(CoachMarkCenter.TRIED_PAUSE)
        assertEquals("category", rig.stepId)
    }

    @Test fun aLoadingScreenSkipsNothing() {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.BudgetHistory)
        rig.stage.visible[CoachMarkTarget.DashboardHistory] = rect
        rig.land()
        rig.stage.route = CoachMarkGuides.HISTORY_ROUTE
        rig.stage.isLoadingScreen = true
        rig.step(33)
        assertEquals("chart", rig.stepId)
        rig.step(10_000)
        rig.step(10_000)
        assertEquals("chart", rig.stepId)
        rig.stage.isLoadingScreen = false
        rig.step(500)
        assertEquals("filter", rig.stepId)
    }

    @Test fun skipAllEndsItAndTheReminderTakesOver() = runBlocking {
        val rig = Rig()
        rig.center.startAutomaticGuideIfDue()
        rig.center.skipAllTapped()
        assertNull(rig.center.session.value)
        assertTrue(rig.store.load("user").isAutoDisabled)
        rig.center.refreshReminder()
        assertEquals(CoachMarkGuideId.SalaryAndExpenses, rig.center.reminder.value)
    }

    @Test fun closingTheReminderHidesItForThreeDays() = runBlocking {
        val rig = Rig()
        rig.center.startAutomaticGuideIfDue()
        rig.center.skipAllTapped()
        rig.center.refreshReminder()
        rig.center.dismissReminder()
        assertNull(rig.center.reminder.value)
        rig.center.refreshReminder()
        assertNull(rig.center.reminder.value)
        rig.time += 3 * 86_400_000L
        rig.center.refreshReminder()
        assertNotNull(rig.center.reminder.value)
    }

    @Test fun aRunningGuideRemindsOfNothing() = runBlocking {
        val rig = Rig()
        rig.center.startAutomaticGuideIfDue()
        rig.center.refreshReminder()
        assertNull(rig.center.reminder.value)
    }

    @Test fun aFinishedReplayShowsItsCheckAndALeftOneDoesNot() = runBlocking {
        val rig = Rig()
        rig.replay(CoachMarkGuideId.BudgetHistory)
        rig.center.skipTapped()
        assertFalse(CoachMarkGuideId.BudgetHistory in rig.center.doneGuides())

        rig.replay(CoachMarkGuideId.BudgetHistory)
        rig.stage.visible[CoachMarkTarget.DashboardHistory] = rect
        rig.land()
        rig.stage.route = CoachMarkGuides.HISTORY_ROUTE
        repeat(8) { rig.step(500) }
        assertEquals("note", rig.stepId)
        rig.land()
        rig.center.nextTapped()
        assertTrue(CoachMarkGuideId.BudgetHistory in rig.center.doneGuides())
    }
}
