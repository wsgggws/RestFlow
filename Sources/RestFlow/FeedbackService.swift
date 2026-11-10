import AppKit
import UserNotifications
import RestFlowCore

@MainActor
final class FeedbackService {
    private var playingSound: NSSound?
    private var musicSample: NSSound?
    private var sampleStop: Task<Void, Never>?

    static func alertSound(_ id: String) -> NSSound? {
        if id == "Glass" { return NSSound(named: "Glass") }
        return AudioAssets.alertURL(id).flatMap { NSSound(contentsOf: $0, byReference: false) }
    }

    func previewMusic(url: URL?, volume: Double) {
        musicSample?.stop(); sampleStop?.cancel()
        guard let url, volume > 0, let sound = NSSound(contentsOf: url, byReference: false) else { return }
        musicSample = sound
        sound.volume = Float(volume)
        sound.play()
        sampleStop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.musicSample?.stop()
        }
    }

    func play(settings: AppSettings, customURL: URL?) {
        playingSound?.stop(); musicSample?.stop(); sampleStop?.cancel()
        guard settings.hasSound else { return }
        let selected: NSSound?
        if let customURL { selected = NSSound(contentsOf: customURL, byReference: false) }
        else { selected = Self.alertSound(settings.selectedSound()) }
        guard let sound = selected else { return }
        sound.volume = Float(settings.volume)
        playingSound = sound
        sound.play()
    }

    func stop() { playingSound?.stop(); musicSample?.stop(); sampleStop?.cancel() }

    nonisolated static let deferAction = "restflow.defer"
    nonisolated static let deferCategory = "restflow.prealert.actions"

    func registerActions(language: AppLanguage) {
        let action = UNNotificationAction(identifier: Self.deferAction, title: language.text("延后 3 分钟", "Delay break by 3 minutes"), options: [])
        let category = UNNotificationCategory(identifier: Self.deferCategory, actions: [action], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func notifyBreak(in seconds: Int, language: AppLanguage, deferToken: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = language.text("该准备休息了", "Time to prepare for a break")
        content.body = language.text("大约 \(seconds) 秒后，所有屏幕将一起进入休息。",
                                     "All displays will take a break in about \(seconds) seconds.")
        // Sound is played by NSSound so that the app's volume is respected.
        content.sound = nil
        if let deferToken {
            content.categoryIdentifier = Self.deferCategory
            content.userInfo = ["focusToken": deferToken]
        }
        let request = UNNotificationRequest(identifier: "restflow.prealert", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("RestFlow notification: %@", error.localizedDescription) }
        }
    }

    func clearNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["restflow.prealert"])
        center.removeDeliveredNotifications(withIdentifiers: ["restflow.prealert"])
    }
}
