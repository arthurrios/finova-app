package com.arthurrios.finova.ui.coachmarks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoachMarkLayoutTest {
    private val bounds = MarkBounds(402f, 874f, MarkInsets(top = 62f, bottom = 34f))
    private val small = MarkBounds(320f, 568f)
    private val gap = CoachMarkLayout.GAP_DP
    private val margin = CoachMarkLayout.MARGIN_DP

    private fun frame(hole: MarkRect?, keyboardTop: Float? = null, within: MarkBounds = bounds, width: Float = 370f, height: Float = 120f) =
        CoachMarkLayout.cardFrame(width, height, hole, within, keyboardTop, gap, margin)

    @Test fun cardGoesBelowATargetNearTheTop() {
        val hole = MarkRect(16f, 120f, 386f, 300f)
        assertTrue(frame(hole)!!.top > hole.bottom)
    }

    @Test fun cardGoesAboveATargetNearTheBottom() {
        val hole = MarkRect(170f, 780f, 230f, 840f)
        assertTrue(frame(hole)!!.bottom < hole.top)
    }

    @Test fun cardStaysClearOfTheKeyboard() {
        assertTrue(frame(MarkRect(16f, 120f, 386f, 300f), keyboardTop = 540f)!!.bottom <= 540f)
    }

    @Test fun cardHidesRatherThanCoverAFormBeingTyped() {
        assertNull(frame(MarkRect(0f, 100f, 402f, 600f), keyboardTop = 600f))
    }

    @Test fun cardSitsOverATallFormWhenNothingIsBeingTyped() {
        assertEquals(bounds.safe.top + margin, frame(MarkRect(0f, 90f, 402f, 874f))!!.top)
    }

    @Test fun cardWithNoTargetIsCentred() {
        val card = frame(null)!!
        assertEquals((bounds.safe.top + bounds.height - bounds.safe.bottom) / 2, (card.top + card.bottom) / 2, 20f)
    }

    @Test fun cardStaysInsideTheSafeArea() {
        listOf(MarkRect(170f, 700f, 230f, 760f), MarkRect(0f, 62f, 402f, 100f), null).forEach { hole ->
            val card = frame(hole)!!
            assertTrue(card.top >= bounds.safe.top)
            assertTrue(card.bottom <= bounds.height - bounds.safe.bottom)
        }
    }

    @Test fun cardFitsOnTheSmallestPhone() {
        val card = frame(MarkRect(16f, 100f, 304f, 160f), within = small, width = 288f, height = 150f)!!
        assertTrue(card.left >= 0 && card.right <= small.width && card.top >= 0 && card.bottom <= small.height)
    }

    @Test fun roundControlGetsARoundHole() {
        assertEquals(30f, CoachMarkLayout.holeRadius(MarkRect(0f, 0f, 62f, 60f), 12f, 8f), 0f)
        assertEquals(12f, CoachMarkLayout.holeRadius(MarkRect(0f, 0f, 300f, 60f), 12f, 8f), 0f)
    }

    // Buttons ----------------------------------------------------------------------------------

    @Test fun aNearFitLeavesTheRowInsteadOfClipping() {
        assertTrue(CoachMarkLayout.buttonsFitOneRow(listOf(120f, 70f, 90f), 338f, 8f, 16f))
        // 130 + 80 + 110 + 2 gaps is 336, which fits a 338 row only by 2.
        assertFalse(CoachMarkLayout.buttonsFitOneRow(listOf(130f, 80f, 110f), 338f, 8f, 16f))
    }

    @Test fun aSingleButtonHasNoGapToCount() {
        assertTrue(CoachMarkLayout.buttonsFitOneRow(listOf(80f), 96f, 8f, 16f))
    }

    // Pager copies -----------------------------------------------------------------------------

    @Test fun theCopyOnTheNextPageIsNotOnThisPage() {
        assertFalse(CoachMarkLayout.isAcross(MarkRect(500f, 100f, 550f, 150f), 402f))
        assertTrue(CoachMarkLayout.isAcross(MarkRect(100f, 100f, 150f, 150f), 402f))
    }

    @Test fun aTargetBelowTheFoldIsStillFoundSoAScrollCanReachIt() {
        assertTrue(CoachMarkLayout.isAcross(MarkRect(16f, 2000f, 386f, 2060f), 402f))
    }

    @Test fun anEmptyTargetIsNotThere() {
        assertFalse(CoachMarkLayout.isAcross(MarkRect(10f, 10f, 10f, 10f), 402f))
    }

    // Touches ----------------------------------------------------------------------------------

    private val hole = MarkRect(170f, 700f, 230f, 760f)
    private val card = MarkRect(16f, 500f, 386f, 620f)

    private fun route(x: Float, y: Float, active: Boolean = true, card: MarkRect? = this.card, hole: MarkRect? = this.hole, live: Boolean = true) =
        CoachMarkTouch.route(x, y, active, card, hole, live)

    @Test fun theTargetTakesTouchesAndTheRestOfTheScreenDoesNot() {
        assertEquals(CoachMarkTouchRoute.Through, route(200f, 730f))
        assertEquals(CoachMarkTouchRoute.Dim, route(20f, 300f))
    }

    @Test fun theCardIsAlwaysReachable() {
        assertEquals(CoachMarkTouchRoute.Card, route(200f, 560f))
    }

    @Test fun betweenStepsTheHoleIsNotLive() {
        assertEquals(CoachMarkTouchRoute.Dim, route(200f, 730f, live = false))
    }

    @Test fun aMarkOnItsWayOutNeverEatsATouch() {
        assertEquals(CoachMarkTouchRoute.Through, route(20f, 300f, active = false))
        assertEquals(CoachMarkTouchRoute.Through, route(200f, 560f, active = false))
    }

    @Test fun aHiddenCardTakesNothing() {
        assertEquals(CoachMarkTouchRoute.Dim, route(200f, 560f, card = null))
    }

    @Test fun aFullWidthHoleKeepsItsRingOnScreen() {
        assertEquals(MarkRect(2f, 10f, 400f, 60f), MarkRect(-6f, 10f, 408f, 60f).clampedAcross(402f, 2f))
    }

    @Test fun rectHelpers() {
        assertNotNull(hole.inflated(6f))
        assertEquals(MarkRect(164f, 694f, 236f, 766f), hole.inflated(6f))
        assertEquals(MarkRect(160f, 690f, 220f, 750f), hole.offset(-10f, -10f))
    }
}
