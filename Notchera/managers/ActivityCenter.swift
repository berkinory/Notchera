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
        Publishers.CombineLatest3(
            ScreenRecordingManager.shared.$isRecording,
            CameraActivityManager.shared.$isActive,
            MicrophoneActivityManager.shared.$isActive
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isRecording, isCameraActive, isMicrophoneActive in
            self?.applyPrivacyState(
                isRecording: isRecording,
                isCameraActive: isCameraActive,
                isMicrophoneActive: isMicrophoneActive
            )
        }
        .store(in: &cancellables)
    }

    private func applyPrivacyState(
        isRecording: Bool,
        isCameraActive: Bool,
        isMicrophoneActive: Bool
    ) {
        var nextBadges: [PrivacyActivityState.Badge] = []

        if isRecording {
            nextBadges.append(.init(kind: .recording))
        }

        if isCameraActive {
            nextBadges.append(.init(kind: .camera))
        } else if isMicrophoneActive {
            nextBadges.append(.init(kind: .microphone))
        }

        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)) {
            privacyState = PrivacyActivityState(badges: nextBadges)
        }
    }
}
