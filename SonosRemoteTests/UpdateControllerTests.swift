import AppKit
import Foundation
import Testing
@testable import SonosRemote

@MainActor
final class FakeUpdater: Updating {
    var automaticallyChecksForUpdates = true
    var lastUpdateCheckDate: Date?
    private(set) var userChecks = 0
    private(set) var backgroundChecks = 0
    func checkForUpdates() { userChecks += 1 }
    func checkForUpdatesInBackground() { backgroundChecks += 1 }
}

/// What the controller sent back to "Sparkle", and what it asked VoiceOver to say.
@MainActor
final class Recorder {
    var choices: [UpdateChoice] = []
    var acknowledgements = 0
    var spoken: [String] = []
    func reply(_ choice: UpdateChoice) { choices.append(choice) }
    func acknowledge() { acknowledgements += 1 }
}

@MainActor
@Suite struct UpdateControllerTests {
    let notes = URL(string: "https://github.com/jens-wedin/sonos-remote/releases/tag/v0.2.5")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    struct Harness {
        let controller: UpdateController
        let updater: FakeUpdater
        let recorder: Recorder
        let defaults: UserDefaults
        let pasteboard: NSPasteboard
    }

    func make(legacyEnabled: Bool? = nil) -> Harness {
        let defaults = UserDefaults(suiteName: "UpdateControllerTests-\(UUID())")!
        if let legacyEnabled { defaults.set(legacyEnabled, forKey: UpdateController.legacyEnabledKey) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("UpdateControllerTests-\(UUID())"))
        let now = self.now
        let controller = UpdateController(defaults: defaults, pasteboard: pasteboard, now: { now })
        let recorder = Recorder()
        controller.announce = { recorder.spoken.append($0) }
        let updater = FakeUpdater()
        controller.attach(updater)
        return Harness(controller: controller, updater: updater, recorder: recorder, defaults: defaults, pasteboard: pasteboard)
    }

    func offer(_ h: Harness, stage: UpdateStage = .notDownloaded) {
        h.controller.updateFound(version: "0.2.5", notesURL: notes, stage: stage, reply: h.recorder.reply)
    }

    @Test func anOfferIsShownAndInstallRepliesExactlyOnce() {
        let h = make()
        offer(h)
        #expect(h.controller.state == .available(version: "0.2.5", notesURL: notes))
        #expect(h.controller.latestKnown == "0.2.5")
        h.controller.install()
        h.controller.install()
        #expect(h.recorder.choices == [.install], "a second click must not call Sparkle's reply again")
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: nil))
        #expect(h.recorder.spoken == ["Downloading update"])
    }

    @Test func skipRepliesSkipAndHidesTheCard() {
        let h = make()
        offer(h)
        h.controller.skip()
        #expect(h.recorder.choices == [.skip])
        #expect(h.controller.state == .idle)
    }

    @Test func progressIsAFractionOfTheExpectedLengthClampedToOne() {
        let h = make()
        offer(h)
        h.controller.install()
        h.controller.downloadStarted()
        h.controller.downloadReceived(length: 10)
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: nil), "unknown length stays indeterminate")
        h.controller.downloadExpected(length: 200)
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: 0.05))
        h.controller.downloadReceived(length: 40)
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: 0.25))
        h.controller.downloadReceived(length: 500)
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: 1), "more bytes than announced never shows over 100%")
    }

    @Test func installingIsAnnouncedOnceAndReadyToInstallRepliesInstall() {
        let h = make()
        offer(h)
        h.controller.install()
        h.controller.extracting()
        h.controller.readyToInstall(reply: h.recorder.reply)
        h.controller.installing()
        #expect(h.controller.state == .installing(version: "0.2.5"))
        #expect(h.recorder.choices == [.install, .install])
        #expect(h.recorder.spoken == ["Downloading update", "Installing update"])
        h.controller.dismissed()
        #expect(h.controller.state == .installing(version: "0.2.5"), "keeps showing Installing… until the app quits")
    }

    @Test func aFailureShowsTryAgainWhichChecksAndInstallsTheNextOfferWithoutAClick() {
        let h = make()
        offer(h)
        h.controller.install()
        h.controller.failed(message: "The download failed.", acknowledgement: h.recorder.acknowledge)
        #expect(h.controller.state == .failed(version: "0.2.5", message: "The download failed."))
        #expect(h.recorder.spoken.last == "Update failed")
        h.controller.dismissed()
        #expect(h.controller.state == .failed(version: "0.2.5", message: "The download failed."), "Sparkle's dismiss must not hide a failure")
        h.controller.retry()
        #expect(h.recorder.acknowledgements == 1)
        #expect(h.updater.userChecks == 1)
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: nil))
        h.controller.dismissed()
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: nil), "the failed session's dismiss must not hide the retry")
        offer(h)
        #expect(h.recorder.choices == [.install, .install])
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: nil))
    }

    @Test func aRetryThatFindsNothingReturnsToIdle() {
        let h = make()
        offer(h)
        h.controller.install()
        h.controller.failed(message: "x", acknowledgement: h.recorder.acknowledge)
        h.controller.retry()
        h.controller.notFound(acknowledgement: h.recorder.acknowledge)
        #expect(h.controller.state == .idle)
        #expect(h.recorder.acknowledgements == 2)
    }

    @Test func dismissingAFailureAcknowledgesItAndHidesTheCard() {
        let h = make()
        offer(h)
        h.controller.install()
        h.controller.failed(message: "x", acknowledgement: h.recorder.acknowledge)
        h.controller.dismissFailure()
        #expect(h.recorder.acknowledgements == 1)
        #expect(h.controller.state == .idle)
    }

    @Test func aBackgroundErrorWithNothingRunningStaysSilent() {
        let h = make()
        h.controller.failed(message: "The feed could not be loaded.", acknowledgement: h.recorder.acknowledge)
        #expect(h.controller.state == .idle)
        #expect(h.recorder.acknowledgements == 1)
        #expect(h.recorder.spoken.isEmpty)
    }

    @Test func anOfferThatIsAlreadyInstallingContinuesWithoutAClick() {
        let h = make()
        offer(h, stage: .installing)
        #expect(h.recorder.choices == [.install])
        #expect(h.controller.state == .installing(version: "0.2.5"))
    }

    @Test func turningChecksOffDismissesTheOfferAndOnAgainChecksAtOnce() {
        let h = make()
        offer(h)
        h.controller.isEnabled = false
        #expect(h.updater.automaticallyChecksForUpdates == false)
        #expect(h.recorder.choices == [.dismiss])
        #expect(h.controller.state == .idle)
        #expect(h.controller.latestKnown == nil)
        h.controller.isEnabled = true
        #expect(h.updater.automaticallyChecksForUpdates == true)
        #expect(h.updater.backgroundChecks == 1)
    }

    @Test func aUserWhoTurnedChecksOffBeforeSparkleStaysOptedOut() {
        let h = make(legacyEnabled: false)
        #expect(h.controller.isEnabled == false)
        #expect(h.updater.automaticallyChecksForUpdates == false)
        #expect(h.defaults.object(forKey: UpdateController.legacyEnabledKey) == nil, "migrated once, then forgotten")
    }

    @Test func panelOpenChecksOnlyWhenTheLastCheckIsADayOld() {
        let h = make()
        h.updater.lastUpdateCheckDate = now.addingTimeInterval(-3_600)
        h.controller.checkIfDue()
        #expect(h.updater.backgroundChecks == 0)
        h.updater.lastUpdateCheckDate = now.addingTimeInterval(-90_000)
        h.controller.checkIfDue()
        #expect(h.updater.backgroundChecks == 1)
        h.updater.lastUpdateCheckDate = nil
        h.controller.checkIfDue()
        #expect(h.updater.backgroundChecks == 1, "never checked: Sparkle's own schedule makes the first check")
        h.controller.isEnabled = false
        h.updater.lastUpdateCheckDate = now.addingTimeInterval(-90_000)
        h.controller.checkIfDue()
        #expect(h.updater.backgroundChecks == 1)
    }

    @Test func updateNowAfterSkippingAsksSparkleAndInstallsTheOffer() {
        let h = make()
        offer(h)
        h.controller.skip()
        #expect(h.controller.canInstall)
        h.controller.install()
        #expect(h.updater.userChecks == 1)
        #expect(h.controller.state == .downloading(version: "0.2.5", fraction: nil))
        offer(h)
        #expect(h.recorder.choices == [.skip, .install])
    }

    @Test func canInstallOnlyWhenAnUpdateIsKnownAndNothingIsRunning() {
        let h = make()
        #expect(!h.controller.canInstall)
        offer(h)
        #expect(h.controller.canInstall)
        h.controller.install()
        #expect(!h.controller.canInstall)
    }

    @Test func copyCommandPutsTheBrewCommandOnThePasteboard() {
        let h = make()
        h.controller.copyCommand()
        #expect(h.pasteboard.string(forType: .string) == "brew update && brew upgrade --cask remote-for-sonos")
    }

    @Test func eachVersionIsAnnouncedOncePerSession() {
        let h = make()
        #expect(h.controller.shouldAnnounce("0.2.5"))
        #expect(!h.controller.shouldAnnounce("0.2.5"))
        #expect(h.controller.shouldAnnounce("0.2.6"))
    }
}
