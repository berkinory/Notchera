import AppKit
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
            let resolvedUUID: String? = {
                guard let rawUUID = space.screenUUID else { return nil }
                if rawUUID == "Main" {
                    return NSScreen.main?.displayUUID
                }
                return rawUUID
            }()

            if let resolvedUUID {
                newStatus[resolvedUUID] = true
            }
        }

        fullscreenStatus = newStatus
    }
}
