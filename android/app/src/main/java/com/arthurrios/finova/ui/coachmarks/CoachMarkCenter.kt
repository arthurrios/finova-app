package com.arthurrios.finova.ui.coachmarks

import com.arthurrios.finova.domain.coachmarks.CoachMarkAdvance
import com.arthurrios.finova.domain.coachmarks.CoachMarkEvent
import com.arthurrios.finova.domain.coachmarks.CoachMarkFacts
import com.arthurrios.finova.domain.coachmarks.CoachMarkGating
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuides
import com.arthurrios.finova.domain.coachmarks.CoachMarkRunMode
import com.arthurrios.finova.domain.coachmarks.CoachMarkSession
import com.arthurrios.finova.domain.coachmarks.CoachMarkState
import com.arthurrios.finova.domain.coachmarks.CoachMarkStateStore
import com.arthurrios.finova.domain.coachmarks.CoachMarkStep
import com.arthurrios.finova.domain.coachmarks.CoachMarkStepKind
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the ledger says. Read-only: nothing above this ever writes to it. */
fun interface CoachMarkDataProviding {
    suspend fun currentFacts(): CoachMarkFacts
}

/** What the engine needs from the screen. The app's is [CoachMarkRegistry]. */
interface CoachMarkStage {
    /** False while another activity, such as the permission prompt, is over the app. */
    val isAppActive: Boolean

    /** The nav entry on top, or the sheet over it. Compared by identity. */
    val topScreen: Any?

    /** The route on top, or null when a sheet is over it. */
    val topRoute: String?
    val isDashboardOnTop: Boolean

    /** In screen pixels; null with no keyboard up. */
    val keyboardTop: Float?

    /** A screen with data on its way: nothing about what is on it can be judged yet. */
    val isLoadingScreen: Boolean

    /** The window layer that draws over the screen on top. */
    val overlayHost: Any?

    fun find(target: CoachMarkTarget): MarkRect?

    /** Whether a form field holds a value right now. */
    fun isFilled(target: CoachMarkTarget): Boolean = false
    fun scrollIntoView(target: CoachMarkTarget)
    fun prepareDashboardForGuide()
}

/** A card's words, as keys: [CoachMarkStrings] turns them into text. */
data class CoachMarkContent(
    val guideTitleKey: String,
    val position: Int,
    val total: Int,
    val messageKey: String,
    val nextKey: String?,
    /** null on a guide's last note, where Done is already the way out. */
    val skipKey: String?,
    val skipAllKey: String?,
)

/** What the overlay draws right now. Null means nothing, and nothing eats a touch. */
data class CoachMarkPresentation(
    val host: Any?,
    val content: CoachMarkContent,
    /** In screen pixels, unpadded. Null is a centred card. */
    val hole: MarkRect?,
    val keyboardTop: Float?,
    /** Moving between targets animates; following a target that moves by itself does not. */
    val animated: Boolean,
    /** The old step has ended and the next has not landed: no card and no live hole. */
    val isBetweenSteps: Boolean = false,
)

/**
 * Runs the guides: decides what starts, shows one mark at a time, and moves on when the user acts.
 * Port of CoachMarkCenter.swift.
 *
 * It only ever watches. Nothing here writes to the ledger or presses a control, so a guide cannot
 * create, change or delete anything; the worst it can do is end early, which it does quietly whenever
 * the screen stops matching what it expected. Everything happens on the main thread.
 */
class CoachMarkCenter(
    private val store: CoachMarkStateStore,
    private val data: CoachMarkDataProviding,
    private val currentUid: () -> String?,
    private val scope: CoroutineScope,
    private val now: () -> Long = System::currentTimeMillis,
) {
    var stage: CoachMarkStage? = null

    private val _session = MutableStateFlow<CoachMarkSession?>(null)
    val session: StateFlow<CoachMarkSession?> = _session.asStateFlow()

    private val _presentation = MutableStateFlow<CoachMarkPresentation?>(null)
    val presentation: StateFlow<CoachMarkPresentation?> = _presentation.asStateFlow()

    private val _reminder = MutableStateFlow<CoachMarkGuideId?>(null)

    /** The setup the dashboard should remind the user of. Never while a guide is running. */
    val reminder: StateFlow<CoachMarkGuideId?> = _reminder.asStateFlow()

    private var autoStart: Job? = null
    private var starting: Job? = null
    private var queuedReplay: CoachMarkGuideId? = null
    private var pendingMonthReset = false

    private var stepStartedAt = 0L
    private var missingSince: Long? = null
    private var settlingRect: MarkRect? = null
    private var settlingSince: Long? = null
    private var didScrollForStep = false
    private var isShowingStep = false
    private var stepScreen: Any? = null
    private var didLeaveStepScreen = false
    private var triedAdvanceAt: Long? = null
    private var keyboardWasUp = false

    // Entry points -----------------------------------------------------------------------------

    /** The dashboard is the only place an automatic guide can begin. */
    fun dashboardDidAppear() {
        val queued = queuedReplay
        if (queued != null) {
            queuedReplay = null
            startReplay(queued)
            return
        }
        scope.launch { refreshReminder() }
        scheduleAutoStart(AUTO_START_DELAY)
    }

    /** A sheet closed, so what was under it is back on top, and a chain may carry on. */
    fun sheetDidClose() {
        if (_session.value == null) scheduleAutoStart(CHAIN_DELAY)
    }

    /** A screen reports that the user really did something. */
    fun post(event: CoachMarkEvent) {
        val session = _session.value ?: return
        if (session.isSatisfied(by = event)) return moveOn(session)
        if (session.isTried(by = event) && isShowingStep && triedAdvanceAt == null) {
            triedAdvanceAt = now() + TRIED_PAUSE
        }
    }

    /** Settings. Works for every user at any time, and whatever is running gives way to it. */
    fun startReplay(guide: CoachMarkGuideId) {
        endSession(Ending.Abandoned)
        _reminder.value = null
        pendingMonthReset = true
        stage?.prepareDashboardForGuide()
        starting?.cancel()
        starting = scope.launch { begin(guide, CoachMarkRunMode.Replay, data.currentFacts()) }
    }

    /** Runs a guide as soon as the dashboard is up, for a launch that opens on one. */
    fun queueReplay(guide: CoachMarkGuideId) {
        queuedReplay = guide
    }

    /** Sign out. Nothing is remembered about the run that was cut off. */
    fun stop() {
        autoStart?.cancel()
        starting?.cancel()
        endSession(Ending.Abandoned)
        _reminder.value = null
    }

    /** Account removed from this phone. */
    fun forget(uid: String) = store.clear(uid)

    /** A guide asked for the current month. True once per request, for the dashboard to act on. */
    fun takeMonthResetRequest(): Boolean = pendingMonthReset.also { pendingMonthReset = false }

    /** For the guides list. */
    suspend fun doneGuides(): Set<CoachMarkGuideId> {
        val facts = data.currentFacts()
        val completed = currentUid()?.let { store.load(it).completed }.orEmpty()
        return CoachMarkGuideId.entries.filter { CoachMarkGating.isSetupDone(it, facts) || it in completed }.toSet()
    }

    // Reminder ---------------------------------------------------------------------------------

    suspend fun refreshReminder() {
        if (_session.value != null) {
            _reminder.value = null
            return
        }
        val uid = currentUid()
        val state = uid?.let(store::load)
        // Stops here for every existing user, as the automatic start does.
        if (state?.isEnrolled != true) {
            _reminder.value = null
            return
        }
        val facts = data.currentFacts()
        _reminder.value = if (_session.value != null) null
        else CoachMarkGating.reminderGuide(store.load(uid), facts, now())
    }

    fun dismissReminder() {
        val uid = currentUid() ?: return
        val state = store.load(uid)
        store.save(state.copy(reminderDismissals = state.reminderDismissals + 1, reminderDismissedAtMillis = now()), uid)
        _reminder.value = null
    }

    // Automatic start --------------------------------------------------------------------------

    private fun scheduleAutoStart(delayMillis: Long) {
        autoStart?.cancel()
        autoStart = scope.launch {
            delay(delayMillis)
            startAutomaticGuideIfDue()
        }
    }

    suspend fun startAutomaticGuideIfDue() {
        val stage = stage ?: return
        if (_session.value != null || !stage.isDashboardOnTop || !stage.isAppActive) return
        val uid = currentUid() ?: return
        var state = store.load(uid)
        // Stops here for every existing user, so they pay for one preference read and no ledger read.
        if (CoachMarkGating.isPermanentlyQuiet(state)) return refreshReminder()

        val facts = data.currentFacts()
        // The read suspended, so the world may have moved on.
        if (_session.value != null || !stage.isDashboardOnTop) return
        state = store.load(uid)
        val enrolled = CoachMarkGating.enrolling(state, facts)
        if (enrolled != state) {
            state = enrolled
            store.save(state, uid)
        }
        val guide = CoachMarkGating.nextAutomaticGuide(state, facts) ?: return refreshReminder()
        store.save(state.copy(autoStarts = state.autoStarts + (guide to (state.autoStarts[guide] ?: 0) + 1)), uid)
        // The facts describe this month, so the steps must run on it, as a replay does.
        pendingMonthReset = true
        stage.prepareDashboardForGuide()
        begin(guide, CoachMarkRunMode.Automatic, facts)
    }

    // Session ----------------------------------------------------------------------------------

    enum class Ending {
        Completed,
        Skipped,
        SkippedAll,

        /** Cut off by something outside the guide. Not the user's decision, so it is not recorded. */
        Abandoned,
    }

    private fun begin(guide: CoachMarkGuideId, mode: CoachMarkRunMode, facts: CoachMarkFacts) {
        val steps = CoachMarkGuides.steps(guide, facts, mode)
        if (steps.isEmpty()) return
        _session.value = CoachMarkSession(guide, mode, steps)
        _reminder.value = null
        resetStepTracking()
    }

    private fun moveOn(session: CoachMarkSession, skipping: Boolean = false) {
        val next = if (skipping) session.skipped() else session.advanced()
        if (next == null) return endSession(Ending.Completed)
        _session.value = next
        resetStepTracking()
        // The old message goes at once, and nothing is touchable until the next lands.
        _presentation.value = _presentation.value?.copy(isBetweenSteps = true)
    }

    private fun resetStepTracking() {
        stepStartedAt = now()
        missingSince = null
        settlingRect = null
        settlingSince = null
        didScrollForStep = false
        isShowingStep = false
        stepScreen = null
        didLeaveStepScreen = false
        triedAdvanceAt = null
    }

    private fun endSession(ending: Ending) {
        val finished = _session.value ?: return
        _session.value = null
        _presentation.value = null
        isShowingStep = false

        currentUid()?.let { uid -> store.save(recording(ending, finished, store.load(uid)), uid) }
        scope.launch { refreshReminder() }
        if (finished.mode != CoachMarkRunMode.Automatic) return
        // Each setup leads into the next: the chain carries on as soon as the dashboard is back.
        if (ending == Ending.Completed || ending == Ending.Skipped) scheduleAutoStart(CHAIN_DELAY)
    }

    // Card buttons -----------------------------------------------------------------------------

    fun nextTapped() {
        val session = _session.value ?: return
        if (!session.step.isAction) moveOn(session)
    }

    fun skipTapped() = endSession(Ending.Skipped)

    fun skipAllTapped() = endSession(Ending.SkippedAll)

    // Tick -------------------------------------------------------------------------------------

    /** Runs about 30 times a second while a guide is up. */
    fun tick() {
        var session = _session.value ?: return
        val stage = stage ?: return
        val time = now()
        if (!stage.isAppActive) return suspend()
        val top = stage.topScreen ?: return suspend()
        val step = session.step

        // Android can put the keyboard away with the field still focused, so this counts as leaving
        // it. Otherwise a filled field would wait for a focus change that never comes.
        val keyboardIsUp = stage.keyboardTop != null
        val filling = (step.triedBy as? CoachMarkAdvance.Event)?.event as? CoachMarkEvent.FieldFilled
        if (keyboardWasUp && !keyboardIsUp && filling != null && stage.isFilled(filling.target)) post(filling)
        keyboardWasUp = keyboardIsUp

        if (isShowingStep && stepScreen == null) stepScreen = top
        when (screenChange(step, stepScreen, top, didLeaveStepScreen)) {
            ScreenChange.Same -> Unit
            ScreenChange.Left -> {
                didLeaveStepScreen = true
                missingSince = null
                return suspend()
            }
            ScreenChange.CameBack -> return moveOn(session)
        }

        if (stage.keyboardTop != null && !step.ownsKeyboard) {
            stepStartedAt = time
            missingSince = null
            return suspend()
        }

        // The user already did what the step asked and is watching the result. A target that went
        // away with it, as a card's other face does, is not a lost target.
        val advanceAt = triedAdvanceAt
        if (advanceAt != null) {
            if (time >= advanceAt) moveOn(session)
            return
        }
        val tried = step.triedBy
        if (isShowingStep && tried is CoachMarkAdvance.TargetVisible && stage.find(tried.target) != null) {
            triedAdvanceAt = time + TRIED_PAUSE
            return
        }

        // First, so a step that was never shown leaves the counter on the card.
        val skip = step.skipIfVisible
        if (!isShowingStep && skip != null && stage.find(skip) != null) return moveOn(session, skipping = true)

        val until = (step.kind as? CoachMarkStepKind.Action)?.until
        if (until is CoachMarkAdvance.TargetVisible && stage.find(until.target) != null) return moveOn(session)
        if (until is CoachMarkAdvance.Screen && stage.topRoute == until.route) return moveOn(session)

        // Absence means nothing until the screen has what it is going to show.
        if (stage.isLoadingScreen) {
            stepStartedAt = time
            return
        }

        val target = step.target ?: return present(null, session)
        val rect = stage.find(target) ?: return handleMissingTarget(step, session, time)

        missingSince = null
        if (!didScrollForStep) {
            didScrollForStep = true
            stage.scrollIntoView(target)
        }

        if (isShowingStep) {
            // Already landed, so follow it. A sheet rises with the keyboard.
            present(rect, session)
        } else if (rect != settlingRect) {
            settlingRect = rect
            settlingSince = time
        } else if (time - (settlingSince ?: time) >= SETTLE_DURATION) {
            present(rect, session)
        }
    }

    private fun handleMissingTarget(step: CoachMarkStep, session: CoachMarkSession, time: Long) {
        val lostSince = missingSince ?: time
        val wasShowing = isShowingStep
        if (wasShowing) missingSince = lostSince

        when (missingTargetResponse(step, wasShowing, time - lostSince, time - stepStartedAt)) {
            MissingTargetResponse.Wait -> Unit
            MissingTargetResponse.Show -> {
                missingSince = null
                present(null, session)
            }
            MissingTargetResponse.StepAside -> {
                val returnTo = step.returnTo
                if (wasShowing && returnTo != null) {
                    _session.value = session.wentBack(returnTo)
                    resetStepTracking()
                }
                suspend()
            }
            MissingTargetResponse.Skip -> moveOn(session, skipping = true)
            // Cannot be done from here, so end rather than leave the user stuck.
            MissingTargetResponse.Abandon -> endSession(Ending.Abandoned)
        }
    }

    private fun present(hole: MarkRect?, session: CoachMarkSession) {
        val stage = stage ?: return
        val current = _presentation.value
        _presentation.value = CoachMarkPresentation(
            host = stage.overlayHost,
            content = content(session),
            hole = hole,
            keyboardTop = stage.keyboardTop,
            animated = !isShowingStep && current != null,
        )
        isShowingStep = true
    }

    /** Steps aside without ending the session. The next tick brings it back. */
    private fun suspend() {
        isShowingStep = false
        settlingRect = null
        settlingSince = null
        _presentation.value = null
    }

    enum class MissingTargetResponse { Wait, Show, StepAside, Skip, Abandon }

    enum class ScreenChange { Same, Left, CameBack }

    companion object {
        /** How long a step waits for its target. Measured only while nothing else explains it. */
        private const val ACTION_TARGET_TIMEOUT = 8_000L
        private const val INFO_TARGET_TIMEOUT = 3_000L

        /** A sheet can be gone for a moment during a transition. Only real absence goes back. */
        private const val LOST_TARGET_GRACE = 500L
        private const val DIM_WHILE_WAITING = 600L

        /** The dashboard fades in and may raise its own prompt just after it appears. */
        private const val AUTO_START_DELAY = 1_200L
        private const val CHAIN_DELAY = 400L

        /** How long a rect must hold still before a mark lands on it. */
        private const val SETTLE_DURATION = 120L

        /** A step with no target on a finished screen. Long enough to rule out one still loading. */
        private const val ABSENT_TARGET_TIMEOUT = 400L

        /** After the user tries something: time to see what it did before the next step. */
        const val TRIED_PAUSE = 800L

        /**
         * What a step does while its target is not on screen. Runs on every tick, so an answer of
         * StepAside for a card that the next tick shows again repeats many times a second: a note
         * that can do without its target must stay Show once it is up.
         */
        fun missingTargetResponse(step: CoachMarkStep, isShowing: Boolean, lostFor: Long, waited: Long): MissingTargetResponse {
            val showsWithoutTarget = step.isTargetOptional && !step.isAction
            if (isShowing) {
                if (showsWithoutTarget) return MissingTargetResponse.Show
                return if (lostFor >= LOST_TARGET_GRACE) MissingTargetResponse.StepAside else MissingTargetResponse.Wait
            }
            val timeout = when {
                step.isAction -> ACTION_TARGET_TIMEOUT
                step.skipsWhenAbsent -> ABSENT_TARGET_TIMEOUT
                else -> INFO_TARGET_TIMEOUT
            }
            if (waited < timeout) {
                // A step that is slow to arrive should not sit on top of the app in the meantime.
                return if (waited >= DIM_WHILE_WAITING) MissingTargetResponse.StepAside else MissingTargetResponse.Wait
            }
            if (showsWithoutTarget) return MissingTargetResponse.Show
            return if (step.isAction) MissingTargetResponse.Abandon else MissingTargetResponse.Skip
        }

        /**
         * Finishing a guide is worth remembering however it was started: it is the check mark in the
         * guides list. Leaving one early from Settings says nothing, so a replay records nothing else.
         */
        fun recording(ending: Ending, session: CoachMarkSession, state: CoachMarkState): CoachMarkState =
            when {
                ending == Ending.Completed -> state.copy(completed = state.completed + session.guide)
                session.mode != CoachMarkRunMode.Automatic -> state
                ending == Ending.Skipped -> state.copy(skipped = state.skipped + session.guide)
                ending == Ending.SkippedAll -> state.copy(isAutoDisabled = true)
                else -> state
            }

        /**
         * A live target can open another screen. That is the user trying it, not a lost target: the
         * note waits out of the way for as long as they stay, then moves on when they return.
         */
        fun screenChange(step: CoachMarkStep, shownOn: Any?, top: Any?, didLeave: Boolean): ScreenChange {
            // A step inside a sheet has returnTo: its screen going away means the sheet was closed.
            if (step.isAction || step.returnTo != null || shownOn == null) return ScreenChange.Same
            if (top !== shownOn) return ScreenChange.Left
            return if (didLeave) ScreenChange.CameBack else ScreenChange.Same
        }

        fun content(session: CoachMarkSession): CoachMarkContent {
            val step = session.step
            val isAutomatic = session.mode == CoachMarkRunMode.Automatic
            val isFinalNote = session.isLastStep && !step.isAction
            return CoachMarkContent(
                guideTitleKey = session.guide.titleKey,
                position = session.shownPosition,
                total = session.shownTotal,
                messageKey = step.textKey,
                nextKey = when {
                    step.isAction -> null
                    session.isLastStep -> "coachMarks.button.done"
                    else -> "coachMarks.button.next"
                },
                skipKey = when {
                    isFinalNote -> null
                    isAutomatic -> "coachMarks.button.skip"
                    else -> "coachMarks.button.close"
                },
                skipAllKey = if (isAutomatic && !isFinalNote) "coachMarks.button.skipAll" else null,
            )
        }
    }
}
