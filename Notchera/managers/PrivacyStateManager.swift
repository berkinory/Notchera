import Combine
import Foundation
import SwiftUI

struct PrivacyState: Equatable {
    enum Kind: String {
        case recording
        case camera
        case microphone
    }

    struct Badge: Identifiable, Equatable {
        let kind: Kind

        var id: Kind {
            kind
        }

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
}

@MainActor
final class PrivacyStateManager: ObservableObject {
    static let shared = PrivacyStateManager()

    @Published private(set) var state = PrivacyState()

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Publishers.CombineLatest3(
            ScreenRecordingManager.shared.$isRecording,
            CameraActivityManager.shared.$isActive,
            MicrophoneActivityManager.shared.$isActive
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isRecording, isCameraActive, isMicrophoneActive in
            self?.applyState(
                isRecording: isRecording,
                isCameraActive: isCameraActive,
                isMicrophoneActive: isMicrophoneActive
            )
        }
        .store(in: &cancellables)
    }

    private func applyState(
        isRecording: Bool,
        isCameraActive: Bool,
        isMicrophoneActive: Bool
    ) {
        var nextBadges: [PrivacyState.Badge] = []

        if isRecording {
            nextBadges.append(.init(kind: .recording))
        }

        if isCameraActive {
            nextBadges.append(.init(kind: .camera))
        } else if isMicrophoneActive {
            nextBadges.append(.init(kind: .microphone))
        }

        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)) {
            state = PrivacyState(badges: nextBadges)
        }
    }
}
