import AppKit
import Foundation
import Observation
import os

/// Asks the release source once a day whether a newer version exists and remembers the answer.
/// Failures never reach the user: they are logged and the next attempt waits a day.
@MainActor @Observable
final class UpdateChecker {
    static let enabledKey = "updateCheckEnabled"
    static let dismissedKey = "dismissedUpdateVersion"
    static let lastCheckKey = "lastUpdateCheck"

    /// Newer than the running version and not dismissed; drives the main-screen card.
    private(set) var available: ReleaseInfo?
    /// Newest newer release seen, dismissed or not; drives the Settings version row.
    private(set) var latestKnown: ReleaseInfo?

    /// The "Check for updates" switch. Off cancels the timer and hides every notice; on restarts the timer and checks at once.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                start()
                Task { await check() }
            } else {
                timer?.cancel()
                timer = nil
                available = nil
                latestKnown = nil
            }
        }
    }

    let brewCommand = "brew upgrade --cask remote-for-sonos"

    @ObservationIgnored private let source: any ReleaseSource
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let initialDelay: Duration
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "updates")
    /// Versions VoiceOver has already been told about this session; the card announces each once.
    @ObservationIgnored private var announcedVersions: Set<String> = []

    init(
        source: any ReleaseSource,
        currentVersion: String,
        defaults: UserDefaults,
        pasteboard: NSPasteboard = .general,
        now: @escaping @Sendable () -> Date = Date.init,
        initialDelay: Duration = .seconds(30),
        interval: Duration = .seconds(86_400)
    ) {
        self.source = source
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.now = now
        self.initialDelay = initialDelay
        self.interval = interval
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    static func live() -> UpdateChecker {
        UpdateChecker(
            source: GitHubReleaseSource(userAgentVersion: AppVersion.short),
            currentVersion: AppVersion.short,
            defaults: .standard
        )
    }

    /// First check `initialDelay` after launch, then every `interval` while enabled. Safe to call more than once.
    func start() {
        guard isEnabled, timer == nil else { return }
        let delay = initialDelay
        let every = interval
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                if let self { await self.check() } else { return }
                try? await Task.sleep(for: every)
            }
        }
    }

    /// The panel calls this on open: runs a check only when the last recorded one is older than a day.
    /// No recorded check means the launch timer has not run yet; it will, so nothing happens here.
    func checkIfDue() {
        let due = TimeInterval(interval.components.seconds)
        guard isEnabled, let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
              now().timeIntervalSince(last) >= due else { return }
        Task { await check() }
    }

    /// One fetch. Success updates the notices; any failure is logged and leaves them unchanged.
    /// `lastUpdateCheck` is written either way so a failing endpoint is not retried before tomorrow.
    func check() async {
        guard isEnabled, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            let release = try await source.latest()
            guard isEnabled else { return }
            apply(release)
        } catch {
            logger.info("update check failed: \(String(describing: error), privacy: .public)")
        }
        defaults.set(now(), forKey: Self.lastCheckKey)
    }

    func dismiss() {
        guard let available else { return }
        defaults.set(available.version, forKey: Self.dismissedKey)
        self.available = nil
    }

    /// True the first time it is asked about a version this session, false afterwards.
    func shouldAnnounce(_ version: String) -> Bool {
        announcedVersions.insert(version).inserted
    }

    func copyCommand() {
        pasteboard.clearContents()
        pasteboard.setString(brewCommand, forType: .string)
    }

    private func apply(_ release: ReleaseInfo) {
        guard SemanticVersion.isNewer(release.version, than: currentVersion) else {
            available = nil
            latestKnown = nil
            return
        }
        latestKnown = release
        available = release.version == defaults.string(forKey: Self.dismissedKey) ? nil : release
    }
}
