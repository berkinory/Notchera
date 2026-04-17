import AVFoundation
import SwiftUI

enum OnboardingStep {
    case welcome
    case cameraPermission
    case accessibilityPermission
    case musicPermission
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "Notchera includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .accessibilityPermission
                        }
                    }
                )
                .transition(.opacity)

            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the Notchera HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await requestAccessibilityPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            NotcheraViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }



    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestAccessibilityPermission() async {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
    }
}
