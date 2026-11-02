package com.arthurrios.finova.domain.coachmarks

/**
 * Per-user memory of the guides. Deliberately thin: whether a setup is done comes from the ledger
 * ([CoachMarkFacts]), and this only holds what the ledger cannot say. Port of CoachMarkState.swift.
 */
data class CoachMarkState(
    /**
     * Decided once, the first time this user reaches the dashboard: true only if they had no data
     * at all. A false here is what keeps an existing user from ever being interrupted, and it must
     * never be recomputed, or the first budget a new user saves would end their own chain.
     */
    val isEnrolled: Boolean? = null,
    /** Skip all. Stops automatic guides for good; Settings and the reminder still work. */
    val isAutoDisabled: Boolean = false,
    val completed: Set<CoachMarkGuideId> = emptySet(),
    val skipped: Set<CoachMarkGuideId> = emptySet(),
    val autoStarts: Map<CoachMarkGuideId, Int> = emptyMap(),
    val reminderDismissals: Int = 0,
    val reminderDismissedAtMillis: Long? = null,
)

/** The few reads and writes the store needs, so tests never touch real preferences. */
interface CoachMarkPreferences {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun remove(key: String)
}

/**
 * Stored per account, so two accounts on one phone never share progress, and signing out and back in
 * finds it where it was. One line per field; a line it cannot read counts as unset, so a damaged
 * value is a blank state rather than a crash.
 */
class CoachMarkStateStore(private val preferences: CoachMarkPreferences) {
    private fun key(uid: String) = "coachMarks.state.$uid"

    fun load(uid: String): CoachMarkState {
        val fields = preferences.getString(key(uid))?.lineSequence()
            ?.mapNotNull { line -> line.split('=', limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
            ?.toMap()
            ?: return CoachMarkState()
        fun guides(name: String) = fields[name].orEmpty().split(',').mapNotNull(CoachMarkGuideId::fromKey).toSet()
        return CoachMarkState(
            isEnrolled = fields["enrolled"]?.toBooleanStrictOrNull(),
            isAutoDisabled = fields["autoDisabled"]?.toBooleanStrictOrNull() ?: false,
            completed = guides("completed"),
            skipped = guides("skipped"),
            autoStarts = fields["autoStarts"].orEmpty().split(',').mapNotNull { pair ->
                val parts = pair.split(':')
                val guide = CoachMarkGuideId.fromKey(parts.firstOrNull()) ?: return@mapNotNull null
                val count = parts.getOrNull(1)?.toIntOrNull() ?: return@mapNotNull null
                guide to count
            }.toMap(),
            reminderDismissals = fields["reminderDismissals"]?.toIntOrNull() ?: 0,
            reminderDismissedAtMillis = fields["reminderDismissedAt"]?.toLongOrNull(),
        )
    }

    fun save(state: CoachMarkState, uid: String) {
        val lines = buildList {
            state.isEnrolled?.let { add("enrolled=$it") }
            add("autoDisabled=${state.isAutoDisabled}")
            add("completed=" + state.completed.joinToString(",") { it.key })
            add("skipped=" + state.skipped.joinToString(",") { it.key })
            add("autoStarts=" + state.autoStarts.entries.joinToString(",") { "${it.key.key}:${it.value}" })
            add("reminderDismissals=${state.reminderDismissals}")
            state.reminderDismissedAtMillis?.let { add("reminderDismissedAt=$it") }
        }
        preferences.putString(key(uid), lines.joinToString("\n"))
    }

    fun clear(uid: String) = preferences.remove(key(uid))
}

/** The rules for what starts by itself. Pure, so the promises made to the user are unit tests. */
object CoachMarkGating {
    /** A guide the user keeps walking away from stops offering itself. Settings still has it. */
    const val MAX_AUTO_STARTS = 3

    /** Closing the reminder this many times means no, and it stops for good. */
    const val MAX_REMINDER_DISMISSALS = 3

    /** How long a closed reminder stays away. */
    const val REMINDER_PAUSE_MILLIS = 3L * 24 * 60 * 60 * 1000

    /** Runs once per user. Returns the state with the enrollment decision made. */
    fun enrolling(state: CoachMarkState, facts: CoachMarkFacts): CoachMarkState =
        if (state.isEnrolled != null) state else state.copy(isEnrolled = !facts.hasAnyData)

    /** True when no fact can change the answer, so the ledger need not be read at all. */
    fun isPermanentlyQuiet(state: CoachMarkState): Boolean = state.isEnrolled == false || state.isAutoDisabled

    fun isSetupDone(guide: CoachMarkGuideId, facts: CoachMarkFacts): Boolean = when (guide) {
        CoachMarkGuideId.FirstBudget -> facts.hasAnyBudget
        CoachMarkGuideId.Allocations -> facts.hasAnyAllocation
        CoachMarkGuideId.SalaryAndExpenses -> facts.hasRecurringTransaction
        CoachMarkGuideId.FirstTransaction -> facts.hasAnyTransaction
        CoachMarkGuideId.CreditCard -> facts.hasCreditCard
        CoachMarkGuideId.BudgetHistory, CoachMarkGuideId.DashboardTour -> false
    }

    /**
     * The setup to remind a new user of, or null. Only for a setup no guide is about to offer, so it
     * never competes with one. An existing user keeps the promise of never being interrupted.
     */
    fun reminderGuide(state: CoachMarkState, facts: CoachMarkFacts, nowMillis: Long): CoachMarkGuideId? {
        if (state.isEnrolled != true) return null
        if (state.reminderDismissals >= MAX_REMINDER_DISMISSALS) return null
        if (nextAutomaticGuide(state, facts) != null) return null
        val dismissedAt = state.reminderDismissedAtMillis
        if (dismissedAt != null && nowMillis - dismissedAt < REMINDER_PAUSE_MILLIS) return null
        return CoachMarkGuideId.automaticChain.firstOrNull { guide ->
            !isSetupDone(guide, facts) && guide !in state.completed &&
                (guide != CoachMarkGuideId.Allocations || facts.hasAnyBudget)
        }
    }

    /** The next guide to run by itself, or null. An enrollment decision must already be made. */
    fun nextAutomaticGuide(state: CoachMarkState, facts: CoachMarkFacts): CoachMarkGuideId? {
        if (state.isEnrolled != true || state.isAutoDisabled) return null
        return CoachMarkGuideId.automaticChain.firstOrNull { guide ->
            !isSetupDone(guide, facts) &&
                guide !in state.completed &&
                guide !in state.skipped &&
                (state.autoStarts[guide] ?: 0) < MAX_AUTO_STARTS &&
                // Allocations split a budget. With no budget the guide would point at nothing useful.
                (guide != CoachMarkGuideId.Allocations || facts.hasAnyBudget)
        }
    }
}
