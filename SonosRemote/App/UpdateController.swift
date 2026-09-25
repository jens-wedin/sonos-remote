import AppKit
import Foundation
import Observation

/// The user's answer to an offered update. Mirrors Sparkle's choice so tests need no Sparkle types.
enum UpdateChoice: Equatable, Sendable { case install, skip, dismiss }

/// How far Sparkle already got with an update it offers.
enum UpdateStage: Equatable, Sendable { case notDownloaded, downloaded, installing }

/// What the update card and the Settings row show.
enum UpdateState: Equatable, Sendable {
    case idle
    case available(version: String, notesURL: URL?)
    /// `fraction` is nil until Sparkle knows the download's length.
    case downloading(version: String, fraction: Double?)
    case installing(version: String)
    case failed(version: String, message: String)

    var version: String? {
        switch self {
        case .idle: nil
        case .available(let version, _), .downloading(let version, _), .installing(let version), .failed(let version, _): version
        }
    }
}

/// Settings' manual "Check now" row, separate from the card's `state`: a version the user skipped can
/// otherwise never be offered again until the next automatic check, since Sparkle drops skipped versions
/// from its own schedule (but not from a user-initiated `checkForUpdates()`).
enum ManualCheck: Equatable, Sendable { case none, checking, upToDate, failed }

/// The part of Sparkle's updater the controller uses. `SparkleUpdater` is the live one; tests use a fake.
@MainActor protocol Updating: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    /// False while Sparkle is still finishing another session; a `checkForUpdates()` made now would be dropped.
    var canCheckForUpdates: Bool { get }
    /// User-initiated: shows an update even if its version was skipped.
    func checkForUpdates()
    func checkForUpdatesInBackground()
}

/// Owns the update state. Sparkle reports through the adapter methods at the bottom (plain values,
/// on the main actor); the card and Settings call the user intents. Sparkle's reply and
/// acknowledgement blocks are held here and called exactly once.
@MainActor @Observable
final class UpdateController {
    /// Written by 0.2.2–0.2.4 when the user switched update checks off; migrated once into Sparkle's setting.
    static let legacyEnabledKey = "updateCheckEnabled"
    /// Leftover keys from the old checker (0.2.2–0.2.4); no longer read, just cleared on attach.
    static let legacyDismissedVersionKey = "dismissedUpdateVersion"
    static let legacyLastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 86_400

    let brewCommand = "brew update && brew upgrade --cask remote-for-sonos"

    private(set) var state: UpdateState = .idle
    /// Newest version Sparkle offered this session, skipped or not. The Settings version row shows it.
    private(set) var latestKnown: String?
    /// Settings' "Check now" row. Independent of `state`: it only ever runs while `state == .idle`.
    private(set) var manualCheck: ManualCheck = .none

    /// The "Check for updates" switch, stored by Sparkle. Off drops any offer; on checks at once.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            updater?.automaticallyChecksForUpdates = isEnabled
            if isEnabled {
                updater?.checkForUpdatesInBackground()
            } else {
                if let reply = pendingReply {
                    pendingReply = nil
                    reply(.dismiss)
                }
                if case .available = state { state = .idle }
                latestKnown = nil
            }
        }
    }

    /// Whether "Update now" can start something: an offer is showing, or a known update was skipped.
    var canInstall: Bool {
        switch state {
        case .available: true
        case .idle: latestKnown != nil && updater != nil
        case .downloading, .installing, .failed: false
        }
    }

    /// Whether Settings' "Check now" can be shown/clicked right now.
    var canCheckNow: Bool {
        state == .idle && updater != nil && manualCheck == .none
    }

    /// Posts a VoiceOver announcement. The app wires it to `AppState.announce`.
    @ObservationIgnored var announce: (String) -> Void = { _ in }

    @ObservationIgnored private var updater: (any Updating)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let now: () -> Date
    /// How long "Update now"/"Try again" waits for Sparkle to call back after being asked to check.
    @ObservationIgnored private let checkTimeout: Duration
    /// How often the deferred check polls `canCheckForUpdates` while waiting for Sparkle to finish another session.
    @ObservationIgnored private let pollInterval: Duration
    /// How long "Up to date"/"Couldn't check" stays on Settings' Version row before `manualCheck` resets to `.none`.
    @ObservationIgnored private let resultDisplay: Duration
    @ObservationIgnored private var pendingReply: ((UpdateChoice) -> Void)?
    @ObservationIgnored private var pendingAcknowledgement: (() -> Void)?
    /// Set when "Update now" or "Try again" had to ask Sparkle first: the next offer installs without another click.
    @ObservationIgnored private var installWhenFound = false
    /// Set when Sparkle couldn't be asked to check because it was still finishing another session; asked again
    /// once that session ends — either from `dismissed()`'s fast path, or from the poll below, whichever
    /// notices first. `dismissed()` alone isn't reliable here: Sparkle can tear that session down (and call
    /// `dismissed()`) synchronously inside the very acknowledgement `retry()` invokes, before this flag is
    /// even set, and it makes no further `dismissed()` call afterwards.
    @ObservationIgnored private var checkWhenSessionEnds = false
    /// Guards against a silently stuck card: fires if Sparkle never calls back after `install()`/`retry()` asked it to check.
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    /// Re-checks `canCheckForUpdates` every `pollInterval` while `checkWhenSessionEnds` is set.
    @ObservationIgnored private var checkPollTask: Task<Void, Never>?
    /// Resets `manualCheck` back to `.none` after `resultDisplay`, so "Check now" can run again.
    @ObservationIgnored private var manualCheckResetTask: Task<Void, Never>?
    @ObservationIgnored private var expectedLength: UInt64 = 0
    @ObservationIgnored private var receivedLength: UInt64 = 0
    /// Step announcements already made in the current attempt ("Downloading update", …).
    @ObservationIgnored private var announcedSteps: Set<String> = []
    /// Versions VoiceOver has already been told about this session.
    @ObservationIgnored private var announcedVersions: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general,
        now: @escaping () -> Date = Date.init,
        checkTimeout: Duration = .seconds(30),
        pollInterval: Duration = .milliseconds(100),
        resultDisplay: Duration = .seconds(3)
    ) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.now = now
        self.checkTimeout = checkTimeout
        self.pollInterval = pollInterval
        self.resultDisplay = resultDisplay
    }

    /// Connects the updater (kept alive here) and adopts its "check automatically" setting.
    func attach(_ updater: any Updating) {
        self.updater = updater
        if defaults.object(forKey: Self.legacyEnabledKey) as? Bool == false {
            updater.automaticallyChecksForUpdates = false
        }
        defaults.removeObject(forKey: Self.legacyEnabledKey)
        defaults.removeObject(forKey: Self.legacyDismissedVersionKey)
        defaults.removeObject(forKey: Self.legacyLastCheckKey)
        isEnabled = updater.automaticallyChecksForUpdates
    }

    // MARK: User intents

    /// "Update now": installs the offered update, or asks Sparkle again for a skipped one and installs it when it arrives.
    func install() {
        switch state {
        case .available(let version, _):
            guard let reply = pendingReply else { return }
            pendingReply = nil
            beginDownload(version)
            reply(.install)
        case .idle:
            guard let version = latestKnown, let updater else { return }
            installWhenFound = true
            beginDownload(version)
            requestCheck(from: updater, for: version)
        case .downloading, .installing, .failed:
            return
        }
    }

    /// ✕ on an offer: Sparkle remembers the skipped version across relaunches.
    func skip() {
        guard case .available = state, let reply = pendingReply else { return }
        pendingReply = nil
        state = .idle
        reply(.skip)
    }

    /// "Try again" after a failure: ends the failed session, then checks and installs without another click.
    func retry() {
        guard case .failed(let version, _) = state, let updater else { return }
        let acknowledge = pendingAcknowledgement
        pendingAcknowledgement = nil
        // Set before acknowledging: Sparkle may dismiss the old session right away, and that must not hide the retry.
        installWhenFound = true
        beginDownload(version)
        acknowledge?()
        requestCheck(from: updater, for: version)
    }

    /// ✕ on a failure.
    func dismissFailure() {
        guard case .failed = state else { return }
        pendingAcknowledgement?()
        pendingAcknowledgement = nil
        state = .idle
    }

    /// Opening the panel: check now when the last check is a day old. Never-checked is left to Sparkle's schedule.
    func checkIfDue() {
        guard isEnabled, let updater, let last = updater.lastUpdateCheckDate,
              now().timeIntervalSince(last) >= Self.checkInterval else { return }
        updater.checkForUpdatesInBackground()
    }

    /// Settings' "Check now": the only way to find a version the user skipped again without waiting for the
    /// next automatic check. User-initiated, so it works even with automatic checks off, and Sparkle ignores
    /// the skip list for it (unlike its own schedule).
    func checkNow() {
        guard case .idle = state, let updater, manualCheck == .none, updater.canCheckForUpdates else { return }
        manualCheck = .checking
        updater.checkForUpdates()
    }

    func copyCommand() {
        pasteboard.clearContents()
        pasteboard.setString(brewCommand, forType: .string)
    }

    /// True the first time it is asked about a version this session, false afterwards.
    func shouldAnnounce(_ version: String) -> Bool {
        announcedVersions.insert(version).inserted
    }

    // MARK: Sparkle adapter (CardUserDriver)

    func updateFound(version: String, notesURL: URL?, stage: UpdateStage, reply: @escaping (UpdateChoice) -> Void) {
        latestKnown = version
        // Cleared unconditionally, before the early return below: an offer that's already installing takes
        // that path and never reaches the normal offer branch, but a manual check must still stop "Checking…".
        if manualCheck == .checking { manualCheck = .none }
        if stage == .installing || installWhenFound {
            resolveWait()
            pendingReply = nil
            if stage == .installing { enterInstalling(version) } else { state = .downloading(version: version, fraction: nil) }
            reply(.install)
            return
        }
        pendingReply?(.dismiss)
        pendingReply = reply
        state = .available(version: version, notesURL: notesURL)
    }

    func downloadStarted() {
        expectedLength = 0
        receivedLength = 0
        updateFraction()
    }

    func downloadExpected(length: UInt64) {
        expectedLength = length
        updateFraction()
    }

    func downloadReceived(length: UInt64) {
        receivedLength += length
        updateFraction()
    }

    func extracting() {
        if let version = runningVersion { enterInstalling(version) }
    }

    /// The user already chose to update, so install and relaunch without asking again — but only while an
    /// update the user started is actually running. "Never silent" must not depend on Sparkle's call order,
    /// so this declines rather than installing something nobody has seen.
    func readyToInstall(reply: @escaping (UpdateChoice) -> Void) {
        guard let version = runningVersion else {
            reply(.dismiss)
            return
        }
        enterInstalling(version)
        reply(.install)
    }

    func installing() {
        if let version = runningVersion { enterInstalling(version) }
    }

    /// Shown only while an update the user started is running; anything else (a failed background check) stays silent.
    func failed(message: String, acknowledgement: @escaping () -> Void) {
        resolveWait()
        // Sparkle has abandoned this session; its reply block is no longer valid to call.
        pendingReply = nil
        switch state {
        case .downloading(let version, _), .installing(let version):
            pendingAcknowledgement = acknowledgement
            state = .failed(version: version, message: message)
            announceStep("Update failed")
        case .available:
            state = .idle
            acknowledgement()
        case .idle:
            // Set before acknowledging, for the same reason as notFound(): dismissed()'s own
            // .checking-clearing fallback must not run before the result is recorded.
            if manualCheck == .checking {
                manualCheck = .failed
                announce("Couldn't check for updates")
                scheduleManualCheckReset()
            }
            acknowledgement()
        case .failed:
            acknowledgement()
        }
    }

    func notFound(acknowledgement: @escaping () -> Void) {
        // Set before acknowledging: Sparkle can call dismissed() synchronously inside the acknowledgement,
        // and dismissed()'s own .checking-clearing fallback must not run before the result is recorded.
        if manualCheck == .checking {
            manualCheck = .upToDate
            announce("Up to date")
            scheduleManualCheckReset()
        }
        acknowledgement()
        guard installWhenFound else { return }
        resolveWait()
        state = .idle
        // The feed no longer offers this version.
        latestKnown = nil
    }

    /// Sparkle ended its session. A failure stays until the user dismisses it; "Installing…" stays until the app quits.
    func dismissed() {
        // Some drivers only ever call dismissed() for an info-only "no update" result — never notFound(),
        // failed(), or updateFound(). Without this, a manual check could stay "Checking…" forever. Harmless
        // when notFound()/failed() already turned .checking into a result before calling their acknowledgement,
        // since by then this simply finds nothing to clear.
        if manualCheck == .checking { manualCheck = .none }
        // The fast path for a deferred check: install()/retry() couldn't ask Sparkle because it was still
        // finishing this very session, and now it has ended. If Sparkle called this from inside the
        // acknowledgement itself (before `checkWhenSessionEnds` was even set) the poll below still catches it.
        startDeferredCheckIfReady()
        guard !installWhenFound else { return }
        switch state {
        case .failed, .installing, .idle:
            return
        case .available:
            // Sparkle has abandoned this session; its reply block is no longer valid to call.
            pendingReply = nil
            state = .idle
        case .downloading:
            state = .idle
        }
    }

    // MARK: Helpers

    private var runningVersion: String? {
        switch state {
        case .downloading(let version, _), .installing(let version): version
        case .idle, .available, .failed: nil
        }
    }

    private func beginDownload(_ version: String) {
        expectedLength = 0
        receivedLength = 0
        announcedSteps = []
        state = .downloading(version: version, fraction: nil)
        announceStep("Downloading update")
    }

    private func updateFraction() {
        guard case .downloading(let version, _) = state else { return }
        let fraction = expectedLength > 0 ? min(1, Double(receivedLength) / Double(expectedLength)) : nil
        state = .downloading(version: version, fraction: fraction)
    }

    private func enterInstalling(_ version: String) {
        state = .installing(version: version)
        announceStep("Installing update")
    }

    private func announceStep(_ message: String) {
        guard announcedSteps.insert(message).inserted else { return }
        announce(message)
    }

    /// Asks Sparkle to check now, unless it's still finishing another session — then both `dismissed()` and a
    /// poll race to ask again as soon as it can. Either way, a watchdog guards against Sparkle never calling
    /// back at all.
    private func requestCheck(from updater: any Updating, for version: String) {
        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        } else {
            checkWhenSessionEnds = true
            startCheckPoll()
        }
        startWatchdog(for: version)
    }

    /// Sparkle may tear its old session down (and call `dismissed()`) synchronously inside the very
    /// acknowledgement `retry()` invokes — before `checkWhenSessionEnds` is even set — and never call
    /// `dismissed()` again for this attempt. So this poll and `dismissed()`'s fast path both watch for
    /// readiness; whichever notices first asks Sparkle to check, exactly once.
    private func startCheckPoll() {
        checkPollTask?.cancel()
        let interval = pollInterval
        checkPollTask = Task { @MainActor [weak self] in
            while true {
                guard let self, !Task.isCancelled, self.checkWhenSessionEnds else { return }
                if self.startDeferredCheckIfReady() { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Runs the check deferred by `requestCheck` as soon as Sparkle can take it. Returns whether it did.
    @discardableResult
    private func startDeferredCheckIfReady() -> Bool {
        guard checkWhenSessionEnds, updater?.canCheckForUpdates == true else { return false }
        checkWhenSessionEnds = false
        checkPollTask?.cancel()
        checkPollTask = nil
        updater?.checkForUpdates()
        return true
    }

    private func startWatchdog(for version: String) {
        watchdogTask?.cancel()
        let timeout = checkTimeout
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            self.checkTimedOut(version: version)
        }
    }

    /// Fires only if nothing (`updateFound`, `notFound`, `failed`) has answered the check by now: never leave
    /// the card silently showing "Downloading…" for a check Sparkle never actually started.
    private func checkTimedOut(version: String) {
        guard installWhenFound, state.version == version else { return }
        watchdogTask = nil
        checkPollTask?.cancel()
        checkPollTask = nil
        checkWhenSessionEnds = false
        installWhenFound = false
        state = .failed(version: version, message: "The update check did not start.")
        announceStep("Update failed")
    }

    /// Clears everything `install()`/`retry()` set up while waiting for Sparkle: an answer has arrived.
    private func resolveWait() {
        installWhenFound = false
        checkWhenSessionEnds = false
        watchdogTask?.cancel()
        watchdogTask = nil
        checkPollTask?.cancel()
        checkPollTask = nil
    }

    /// After showing "Up to date"/"Couldn't check" on the Version row, resets `manualCheck` so
    /// `checkNow()` can run again.
    private func scheduleManualCheckReset() {
        manualCheckResetTask?.cancel()
        let delay = resultDisplay
        manualCheckResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.manualCheckResetTask = nil
            self.manualCheck = .none
        }
    }
}
