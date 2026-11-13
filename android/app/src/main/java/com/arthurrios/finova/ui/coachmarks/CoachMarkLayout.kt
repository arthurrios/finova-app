package com.arthurrios.finova.ui.coachmarks

/** A rectangle in pixels. Plain numbers, so layout and the touch rule are unit tests. */
data class MarkRect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top

    fun contains(x: Float, y: Float): Boolean = x >= left && x < right && y >= top && y < bottom
    fun offset(dx: Float, dy: Float) = MarkRect(left + dx, top + dy, right + dx, bottom + dy)
    fun inflated(by: Float) = MarkRect(left - by, top - by, right + by, bottom + by)
    fun clampedAcross(width: Float, inset: Float) = copy(left = maxOf(left, inset), right = minOf(right, width - inset))
}

data class MarkInsets(val left: Float = 0f, val top: Float = 0f, val right: Float = 0f, val bottom: Float = 0f)

/** The window a mark is laid out in, in pixels. */
data class MarkBounds(val width: Float, val height: Float, val safe: MarkInsets = MarkInsets())

/** Where the card goes. Pure, so small screens and the keyboard can be tested with numbers. */
object CoachMarkLayout {
    const val GAP_DP = 12f
    const val MARGIN_DP = 16f
    const val MAX_CARD_WIDTH_DP = 400f
    const val HOLE_PADDING_DP = 6f

    /** How much of a target must be across the window before it counts as on this page. */
    private const val MIN_ACROSS_FRACTION = 0.5f

    /**
     * `null` means the card should hide: the keyboard is up and no spot leaves the form usable. It
     * reappears when the keyboard goes down.
     */
    fun cardFrame(
        cardWidth: Float,
        cardHeight: Float,
        hole: MarkRect?,
        bounds: MarkBounds,
        keyboardTop: Float?,
        gap: Float,
        margin: Float,
    ): MarkRect? {
        val x = (bounds.width - cardWidth) / 2
        val top = bounds.safe.top + margin
        val bottom = (keyboardTop ?: (bounds.height - bounds.safe.bottom)) - margin
        fun at(y: Float) = MarkRect(x, y, x + cardWidth, y + cardHeight)

        if (hole == null) return at(top + maxOf(0f, (bottom - top - cardHeight) / 2))

        val roomBelow = bottom - (hole.bottom + gap)
        val roomAbove = (hole.top - gap) - top
        if (roomBelow >= cardHeight) return at(hole.bottom + gap)
        if (roomAbove >= cardHeight) return at(hole.top - gap - cardHeight)
        // A hole taller than the free space, such as a full form. Over its top is the least harmful
        // place, but not while the user is typing into it.
        return if (keyboardTop == null) at(top) else null
    }

    /**
     * A round control gets a round hole: width and height within this of each other.
     * Returns the corner radius of a hole.
     */
    fun holeRadius(hole: MarkRect, cardRadius: Float, roundWithin: Float): Float =
        if (kotlin.math.abs(hole.width - hole.height) < roundWithin) hole.height / 2 else cardRadius

    /** Fits one row with some margin: a near fit would clip a title. */
    fun buttonsFitOneRow(widths: List<Float>, available: Float, spacing: Float, margin: Float): Boolean =
        widths.sum() + spacing * maxOf(0, widths.size - 1) + margin <= available

    /**
     * Whether a target counts as on this page. Only the horizontal test can rule it out: a pager
     * holds one copy per month, side by side, and the one to the side is not the one the user sees.
     * Vertical distance never rules it out, because a scroll brings it into view.
     */
    fun isAcross(target: MarkRect, windowWidth: Float): Boolean {
        if (target.width <= 0f || target.height <= 0f) return false
        val across = minOf(target.right, windowWidth) - maxOf(target.left, 0f)
        return across >= target.width * MIN_ACROSS_FRACTION
    }
}

/** Who gets a touch. The whole rule, so nothing else in the app has to know a mark is up. */
enum class CoachMarkTouchRoute {
    /** Not ours: the window's own views handle it, exactly as with no mark up. */
    Through,

    /** The card's buttons. */
    Card,

    /** The dim layer eats it. It never does anything but put a keyboard away. */
    Dim,
}

object CoachMarkTouch {
    fun route(
        x: Float,
        y: Float,
        isActive: Boolean,
        card: MarkRect?,
        hole: MarkRect?,
        isHoleTouchable: Boolean,
    ): CoachMarkTouchRoute = when {
        !isActive -> CoachMarkTouchRoute.Through
        card != null && card.contains(x, y) -> CoachMarkTouchRoute.Card
        isHoleTouchable && hole != null && hole.contains(x, y) -> CoachMarkTouchRoute.Through
        else -> CoachMarkTouchRoute.Dim
    }
}
