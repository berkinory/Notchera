import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct HUDSettingsView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @Default(.enableGradient) var enableGradient
    @Default(.hudReplacement) var hudReplacement
    @Default(.showVolumeIndicator) var showVolumeIndicator
    @Default(.showBrightnessIndicator) var showBrightnessIndicator
    @Default(.showBacklightIndicator) var showBacklightIndicator
    @Default(.showCapsLockIndicator) var showCapsLockIndicator
    @Default(.showInputSourceIndicator) var showInputSourceIndicator
    @Default(.showFocusIndicator) var showFocusIndicator
    @Default(.showBluetoothAudioIndicator) var showBluetoothAudioIndicator
    @Default(.animateBluetoothAudioIndicator) var animateBluetoothAudioIndicator
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.headline)
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                        .disabled(!accessibilityAuthorized)
                }

                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            Section {
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
            } header: {
                SettingsSectionHeader(title: "General")
            }
            .disabled(!hudReplacement)

            Section {
                Defaults.Toggle(key: .showVolumeIndicator) {
                    Text("Show volume indicator")
                }

                Defaults.Toggle(key: .showBrightnessIndicator) {
                    Text("Show brightness indicator")
                }

                Defaults.Toggle(key: .showBacklightIndicator) {
                    Text("Show keyboard backlight indicator")
                }

                Defaults.Toggle(key: .showCapsLockIndicator) {
                    Text("Show Caps Lock indicator")
                }

                Defaults.Toggle(key: .showInputSourceIndicator) {
                    Text("Show input language indicator")
                }

                Defaults.Toggle(key: .showFocusIndicator) {
                    Text("Show Focus mode indicator")
                }

                Defaults.Toggle(key: .showBluetoothAudioIndicator) {
                    Text("Show Bluetooth audio notifications")
                }

                Defaults.Toggle(key: .animateBluetoothAudioIndicator) {
                    Text("Use animated Bluetooth icons")
                }

                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show battery notifications")
                }

                Defaults.Toggle(key: .enableScreenRecordingDetection) {
                    Text("Show screen recording toast")
                }
            } header: {
                SettingsSectionHeader(title: "Indicators")
            } footer: {
                Text("Replace system HUD acts as the master switch. When it is off, no indicator runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!hudReplacement)
        }
        .scrollContentBackground(.hidden)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}
