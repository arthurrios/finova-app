//
//  CoachMarkCenter.swift
//  Finova
//

import UIKit

/// What the engine needs from navigation.
protocol CoachMarkNavigating: AnyObject {
    var isDashboardOnTop: Bool { get }
    /// Brings the dashboard to the front on the current month, for a guide started from Settings.
    func prepareDashboardForGuide()
}

/// Runs the guides: decides what starts, shows one mark at a time, and moves on when the user acts.
///
/// It only ever watches. Nothing here writes to the ledger or presses a control, so a guide cannot
/// create, change or delete anything; the worst it can do is end early, which it does quietly
/// whenever the screen stops matching what it expected. Everything happens on the main thread.
final class CoachMarkCenter {
    static let shared = CoachMarkCenter()

    weak var navigator: CoachMarkNavigating?

    /// How long a step waits for its target. Measured only while nothing else explains the absence.
    private static let actionTargetTimeout: TimeInterval = 8
    private static let infoTargetTimeout: TimeInterval = 3
    /// A sheet can be gone for a moment during a transition. Only a real absence goes back a step.
    private static let lostTargetGrace: TimeInterval = 0.5
    private static let dimWhileWaiting: TimeInterval = 0.6
    /// The dashboard fades in and may raise its own alert just after it appears.
    private static let autoStartDelay: TimeInterval = 1.2
    /// How long a rect must hold still before a mark lands on it.
    private static let settleDuration: TimeInterval = 0.12

    private let store: CoachMarkStateStore
    private let dataProvider: CoachMarkDataProviding
    private(set) var session: CoachMarkSession?

    private var overlayWindow: CoachMarkOverlayWindow?
    private var displayLink: CADisplayLink?
    private var keyboardFrame: CGRect?
    private var autoStartWork: DispatchWorkItem?

    private var stepStartedAt = Date()
    private var missingSince: Date?
    private var settlingRect: CGRect?
    private var settlingSince: Date?
    private var didScrollForStep = false
    private var isShowingStep = false
    private var isFadingOut = false
    private var hasAnnouncedStep = false
    #if DEMO
    private var didStartDemoReplay = false
    #endif

    init(
        store: CoachMarkStateStore = CoachMarkStateStore(),
        dataProvider: CoachMarkDataProviding = CoachMarkDataProvider()
    ) {
        self.store = store
        self.dataProvider = dataProvider

        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(
            self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private var currentUID: String? {
        UserDefaultsManager.getUser()?.firebaseUID ?? UIDUserDefaultsManager.shared.currentUserUID
    }

    // MARK: - Entry points

    /// The dashboard is the only place an automatic guide can begin.
    func dashboardDidAppear() {
        #if DEMO
        if session == nil, !didStartDemoReplay, let guide = CoachMarkFreshUserMode.replayGuide {
            didStartDemoReplay = true
            startReplay(guide)
            return
        }
        #endif
        scheduleAutoStart(after: Self.autoStartDelay)
    }

    /// A scene reports that the user really did something.
    func post(_ event: CoachMarkEvent) {
        guard var session, session.isSatisfied(by: event) else { return }
        moveOn(&session)
    }

    /// Settings. Works for every user at any time, and whatever is running gives way to it.
    func startReplay(_ guide: CoachMarkGuideID) {
        endSession(.abandoned)
        navigator?.prepareDashboardForGuide()
        begin(guide, mode: .replay, facts: dataProvider.currentFacts())
    }

    /// Sign out. Nothing is remembered about the run that was cut off.
    func stop() {
        autoStartWork?.cancel()
        endSession(.abandoned)
    }

    /// For the guides list.
    func isSetupDone(_ guide: CoachMarkGuideID) -> Bool {
        if CoachMarkGating.isSetupDone(guide, facts: dataProvider.currentFacts()) { return true }
        return currentUID.map { store.load(uid: $0).completed.contains(guide) } ?? false
    }

    // MARK: - Automatic start

    private func scheduleAutoStart(after delay: TimeInterval) {
        autoStartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startAutomaticGuideIfDue() }
        autoStartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startAutomaticGuideIfDue() {
        guard session == nil, navigator?.isDashboardOnTop == true, let uid = currentUID else { return }

        #if DEMO
        CoachMarkFreshUserMode.applyIfNeeded(uid: uid, store: store)
        #endif

        var state = store.load(uid: uid)
        // Stops here for every existing user, so they pay for one defaults read and no ledger read.
        guard !CoachMarkGating.isPermanentlyQuiet(state) else { return }

        let facts = dataProvider.currentFacts()
        let enrolled = CoachMarkGating.enrolling(state, facts: facts)
        if enrolled != state {
            state = enrolled
            store.save(state, uid: uid)
        }

        guard let guide = CoachMarkGating.nextAutomaticGuide(state: state, facts: facts) else { return }
        state.autoStarts[guide, default: 0] += 1
        store.save(state, uid: uid)
        begin(guide, mode: .automatic, facts: facts)
    }

    // MARK: - Session

    private enum Ending {
        case completed
        case skipped
        case skippedAll
        /// Cut off by something outside the guide. Not the user's decision, so it is not recorded.
        case abandoned
    }

    private func begin(_ guide: CoachMarkGuideID, mode: CoachMarkRunMode, facts: CoachMarkFacts) {
        let steps = CoachMarkGuides.steps(for: guide, facts: facts, mode: mode)
        guard !steps.isEmpty else { return }
        session = CoachMarkSession(guide: guide, mode: mode, steps: steps)
        resetStepTracking()
        startTicking()
    }

    private func moveOn(_ session: inout CoachMarkSession, skipping: Bool = false) {
        guard skipping ? session.skipStep() : session.advance() else {
            self.session = session
            endSession(.completed)
            return
        }
        self.session = session
        resetStepTracking()
        overlayWindow?.overlay.prepareForNextStep()
    }

    private func resetStepTracking() {
        stepStartedAt = Date()
        missingSince = nil
        settlingRect = nil
        settlingSince = nil
        didScrollForStep = false
        isShowingStep = false
        hasAnnouncedStep = false
    }

    private func endSession(_ ending: Ending) {
        guard let finished = session else { return }
        session = nil
        stopTicking()
        fadeOut(removingWindow: true)

        guard finished.mode == .automatic else { return }
        if let uid = currentUID {
            var state = store.load(uid: uid)
            switch ending {
            case .completed: state.completed.insert(finished.guide)
            case .skipped: state.skipped.insert(finished.guide)
            case .skippedAll: state.isAutoDisabled = true
            case .abandoned: break
            }
            store.save(state, uid: uid)
        }
        // Each setup leads into the next: the chain carries on as soon as the dashboard is back.
        if ending == .completed || ending == .skipped {
            scheduleAutoStart(after: 0.4)
        }
    }

    // MARK: - Tick

    private func startTicking() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard var session, let window = appWindow() else { return }
        guard UIApplication.shared.applicationState == .active,
              let top = CoachMarkTargetResolver.topViewController(from: window.rootViewController)
        else { return suspend() }

        // An alert or a keyboard that is not this step's: step aside and wait for as long as it
        // takes. The user may read an alert for a minute, and that is not a missing target.
        let step = session.step
        if top is UIAlertController || (isKeyboardUp(in: window) && !step.ownsKeyboard) {
            stepStartedAt = Date()
            missingSince = nil
            return suspend()
        }

        if isTransitioning(top) { return }

        // First, so a step that was never shown leaves the counter on the card.
        if !isShowingStep, let skip = step.skipIfVisible,
           CoachMarkTargetResolver.find(skip, in: top.view, within: window) != nil {
            return moveOn(&session, skipping: true)
        }
        if case .action(.targetVisible(let target)) = step.kind,
           CoachMarkTargetResolver.find(target, in: top.view, within: window) != nil {
            return moveOn(&session)
        }
        if case .action(.screen(let name)) = step.kind, String(describing: type(of: top)) == name {
            return moveOn(&session)
        }

        guard let target = step.target else {
            return present(hole: nil, in: window)
        }
        guard let view = CoachMarkTargetResolver.find(target, in: top.view, within: window) else {
            return handleMissingTarget(of: step, session: &session, in: window)
        }

        missingSince = nil
        if !didScrollForStep {
            didScrollForStep = true
            if CoachMarkTargetResolver.scrollIntoView(view) { return }
        }

        let rect = view.convert(view.bounds, to: window)
        if isShowingStep {
            // Already landed, so follow it. A sheet rises with the keyboard.
            present(hole: rect, in: window)
        } else if rect != settlingRect {
            settlingRect = rect
            settlingSince = Date()
        } else if let since = settlingSince, Date().timeIntervalSince(since) >= Self.settleDuration {
            present(hole: rect, in: window)
        }
    }

    private func handleMissingTarget(
        of step: CoachMarkStep, session: inout CoachMarkSession, in window: UIWindow
    ) {
        let now = Date()
        if isShowingStep {
            let since = missingSince ?? now
            missingSince = since
            guard now.timeIntervalSince(since) >= Self.lostTargetGrace else { return }
            if let returnTo = step.returnTo {
                session.goBack(to: returnTo)
                self.session = session
                resetStepTracking()
            }
            suspend()
            return
        }

        let waited = now.timeIntervalSince(stepStartedAt)
        // A step that is slow to arrive should not sit on top of the app in the meantime.
        if waited >= Self.dimWhileWaiting { suspend() }

        let timeout = step.isAction ? Self.actionTargetTimeout : Self.infoTargetTimeout
        guard waited >= timeout else { return }
        if step.isTargetOptional {
            present(hole: nil, in: window)
        } else if step.isAction {
            // Cannot be done from here, so end rather than leave the user stuck.
            endSession(.abandoned)
        } else {
            moveOn(&session, skipping: true)
        }
    }

    private func isTransitioning(_ top: UIViewController) -> Bool {
        top.transitionCoordinator != nil || top.navigationController?.transitionCoordinator != nil
    }

    private func isKeyboardUp(in window: UIWindow) -> Bool {
        keyboardTop(in: window) != nil
    }

    private func keyboardTop(in window: UIWindow) -> CGFloat? {
        guard let frame = keyboardFrame, frame.height > 0, frame.minY < window.bounds.maxY else {
            return nil
        }
        return frame.minY
    }

    // MARK: - Presentation

    private func appWindow() -> UIWindow? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first { !($0 is CoachMarkOverlayWindow) && $0.rootViewController != nil }
    }

    private func present(hole: CGRect?, in window: UIWindow) {
        guard let session else { return }
        let keyboardTop = keyboardTop(in: window)

        // The form's own fields are what a VoiceOver user needs, and the announcement carries the
        // message, so the overlay stays out of the way entirely.
        if UIAccessibility.isVoiceOverRunning, session.step.ownsKeyboard {
            if !hasAnnouncedStep {
                hasAnnouncedStep = true
                UIAccessibility.post(notification: .announcement, argument: session.step.textKey.localized)
            }
            isShowingStep = true
            suspend()
            return
        }

        guard let overlayWindow = makeOverlayWindowIfNeeded(for: window) else { return }
        let overlay = overlayWindow.overlay

        if isShowingStep {
            overlay.show(
                hole: hole, touchable: session.step.isAction, keyboardTop: keyboardTop, animated: false,
                plain: session.step.isPlain)
            return
        }

        let wasVisible = !overlayWindow.isHidden && overlay.alpha > 0 && !isFadingOut
        isFadingOut = false
        isShowingStep = true
        configureBubble(overlay, for: session)
        overlay.isActive = true
        overlayWindow.isHidden = false
        overlay.show(
            hole: hole, touchable: session.step.isAction, keyboardTop: keyboardTop, animated: wasVisible,
            plain: session.step.isPlain)

        if wasVisible {
            crossfadeBubble(overlay)
        } else {
            overlay.layer.removeAllAnimations()
            overlay.bubble.alpha = 1
            overlay.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                overlay.alpha = 1
            }
        }
        announce(session, overlay: overlay)
    }

    private func crossfadeBubble(_ overlay: CoachMarkOverlayView) {
        overlay.bubble.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0.1, options: []) { overlay.bubble.alpha = 1 }
    }

    private func announce(_ session: CoachMarkSession, overlay: CoachMarkOverlayView) {
        guard !hasAnnouncedStep else { return }
        hasAnnouncedStep = true
        // Info steps hold the user here, so VoiceOver stays with the card. In an action step it must
        // be able to leave the card and reach the target, which sits in the window underneath.
        overlay.accessibilityViewIsModal = !session.step.isAction
        UIAccessibility.post(notification: .screenChanged, argument: overlay.bubble)
    }

    private func makeOverlayWindowIfNeeded(for window: UIWindow) -> CoachMarkOverlayWindow? {
        if let overlayWindow { return overlayWindow }
        guard let scene = window.windowScene else { return nil }

        let newWindow = CoachMarkOverlayWindow(windowScene: scene)
        newWindow.frame = window.frame
        let bubble = newWindow.overlay.bubble
        bubble.onNext = { [weak self] in self?.nextTapped() }
        bubble.onSkip = { [weak self] in self?.endSession(.skipped) }
        bubble.onSkipAll = { [weak self] in self?.endSession(.skippedAll) }
        newWindow.overlay.onDimTapped = { [weak self] in
            self?.appWindow()?.endEditing(true)
        }
        overlayWindow = newWindow
        return newWindow
    }

    private func nextTapped() {
        guard var session, !session.step.isAction else { return }
        moveOn(&session)
    }

    private func configureBubble(_ overlay: CoachMarkOverlayView, for session: CoachMarkSession) {
        overlay.bubble.configure(Self.content(for: session))
    }

    static func content(for session: CoachMarkSession) -> CoachMarkBubbleView.Content {
        let step = session.step
        let caption = String(
            format: "coachMarks.caption".localized,
            session.guide.titleKey.localized, session.shownPosition, session.shownTotal)
        let isAutomatic = session.mode == .automatic
        let isFinalNote = session.isLastStep && !step.isAction

        return CoachMarkBubbleView.Content(
            caption: caption,
            message: step.textKey.localized,
            nextTitle: step.isAction
                ? nil
                : (session.isLastStep ? "coachMarks.button.done" : "coachMarks.button.next").localized,
            skipTitle: isFinalNote
                ? nil
                : (isAutomatic ? "coachMarks.button.skip" : "coachMarks.button.close").localized,
            skipAllTitle: isAutomatic && !isFinalNote ? "coachMarks.button.skipAll".localized : nil)
    }

    /// Steps aside without ending the session. The next tick brings it back.
    private func suspend() {
        isShowingStep = false
        settlingRect = nil
        settlingSince = nil
        fadeOut(removingWindow: false)
    }

    private func fadeOut(removingWindow: Bool) {
        guard let overlayWindow else { return }
        let overlay = overlayWindow.overlay
        // Immediately, not after the fade: a mark leaving must not eat the next touch.
        overlay.isActive = false

        let finish = { [weak self, weak overlayWindow] in
            guard let self, let overlayWindow else { return }
            self.isFadingOut = false
            overlayWindow.isHidden = true
            if removingWindow, self.session == nil, self.overlayWindow === overlayWindow {
                self.overlayWindow = nil
            }
        }
        guard !overlayWindow.isHidden, !isFadingOut else {
            if overlayWindow.isHidden { finish() }
            return
        }
        isFadingOut = true
        UIView.animate(
            withDuration: 0.2, delay: 0, options: [.beginFromCurrentState],
            animations: { overlay.alpha = 0 },
            completion: { _ in
                // A new mark may have landed during the fade. It owns the window now.
                if overlay.isActive { return }
                finish()
            })
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    }

    @objc private func keyboardWillHide() {
        keyboardFrame = nil
    }
}
