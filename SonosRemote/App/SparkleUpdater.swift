import Foundation
import os
import Sparkle

/// The live `Updating`: owns Sparkle's updater and the card-driving user driver.
/// Nil under XCTest (tests never reach the feed) or when Sparkle cannot start (logged; the card simply never appears).
@MainActor
final class SparkleUpdater: NSObject, Updating, SPUUpdaterDelegate {
    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "updates")
    /// The user driver Sparkle reports to (SPUUpdater retains it too; kept here so its owner is explicit).
    private let driver: CardUserDriver
    private var updater: SPUUpdater!

    init?(controller: UpdateController) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        driver = CardUserDriver(controller: controller)
        super.init()
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do {
            try updater.start()
        } catch {
            logger.error("Sparkle did not start: \(error.localizedDescription, privacy: .private)")
            return nil
        }
        self.updater = updater
        logger.info("Sparkle started; automatic checks \(updater.automaticallyChecksForUpdates ? "on" : "off", privacy: .public)")
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugCheckNow") { updater.checkForUpdatesInBackground() }
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    func checkForUpdates() { updater.checkForUpdates() }

    func checkForUpdatesInBackground() { updater.checkForUpdatesInBackground() }

    #if DEBUG
    /// Debug builds can point at a local feed: `open SonosRemote.app --args -debugFeedURL http://localhost:8765/appcast.xml`.
    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "debugFeedURL")
    }
    #endif
}
