import Combine
import Foundation
import SwiftUI

struct PrivacyActivityState: Equatable {
    enum Kind: String {
        case recording
        case camera
        case microphone
    }

    struct Badge: Identifiable, Equatable {
        let kind: Kind

        var id: Kind { kind }
        var symbol: String {
            switch kind {
            case .recording:
                "record.circle.fill"
            case .camera:
                "video.fill"
            case .microphone:
                "mic.fill"
            }
        }

        var tint: Color {
            switch kind {
            case .recording:
                .red
            case .camera:
                .green
            case .microphone:
                .yellow
            }
        }
    }

    var badges: [Badge] = []

    var isActive: Bool {
        !badges.isEmpty
    }

    var primaryBadge: Badge? {
        badges.first
    }
}

@MainActor
final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()

    @Published private(set) var privacyState = PrivacyActivityState()

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        ScreenRecordingManager.shared.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                self?.applyRecordingState(isRecording)
            }
            .store(in: &cancellables)
    }

    private func applyRecordingState(_ isRecording: Bool) {
        var nextBadges: [PrivacyActivityState.Badge] = []

        if isRecording {
            nextBadges.append(.init(kind: .recording))
        }

        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)) {
            privacyState = PrivacyActivityState(badges: nextBadges)
        }
    }
}
