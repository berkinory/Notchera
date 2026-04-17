import Combine
import Defaults
import Foundation
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()

    @Published var fullscreenStatus: [String: Bool] = [:]

    private var monitorTask: Task<Void, Never>?

    private init() {
        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
    }

    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }

    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]

        for space in spaces {
            if let uuid = space.screenUUID,
               let musicSourceBundle = MusicManager.shared.bundleIdentifier
            {
                newStatus[uuid] = space.runningApps.contains(musicSourceBundle)
            }
        }

        fullscreenStatus = newStatus
    }
}
