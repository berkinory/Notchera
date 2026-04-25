import AVFoundation
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
    @Default(.systemEventIndicatorShadow) var systemEventIndicatorShadow
    @Default(.showBacklightIndicator) var showBacklightIndicator
    @Default(.showSystemValueInHUD) var showSystemValueInHUD
    @Default(.showHUDOnLockScreen) var showHUDOnLockScreen
    @Default(.showCapsLockIndicator) var showCapsLockIndicator
    @Default(.showInputSourceIndicator) var showInputSourceIndicator
    @Default(.showFocusIndicator) var showFocusIndicator
    @Default(.showBluetoothAudioIndicator) var showBluetoothAudioIndicator
    @Default(.animateBluetoothAudioIndicator) var animateBluetoothAudioIndicator
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.showCLINotifications) var showCLINotifications
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    @State private var cliInstallState = CLIToolManager.installState()
    @State private var cliInstallError: String?

    private var hudEnabledBinding: Binding<Bool> {
        Binding(
            get: { hudReplacement },
            set: { newValue in
                hudReplacement = newValue

                if !newValue {
                    enableGradient = false
                    systemEventIndicatorShadow = false
                    showVolumeIndicator = false
                    showBrightnessIndicator = false
                    showBacklightIndicator = false
                    showSystemValueInHUD = false
                    showHUDOnLockScreen = false
                    showCapsLockIndicator = false
                    showInputSourceIndicator = false
                    showFocusIndicator = false
                    showBluetoothAudioIndicator = false
                    animateBluetoothAudioIndicator = false
                    showPowerStatusNotifications = false
                    enableScreenRecordingDetection = false
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable HUD", isOn: hudEnabledBinding)
                    .disabled(!accessibilityAuthorized)

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

            if hudReplacement {
                Section {
                    HStack(spacing: 8) {
                        HUDProgressStyleOptionCard(
                            title: "Hierarchical",
                            isSelected: !enableGradient,
                            usesGradient: false,
                            glowEnabled: systemEventIndicatorShadow,
                            showsValue: showSystemValueInHUD,
                            action: {
                                enableGradient = false
                            }
                        )

                        HUDProgressStyleOptionCard(
                            title: "Gradient",
                            isSelected: enableGradient,
                            usesGradient: true,
                            glowEnabled: systemEventIndicatorShadow,
                            showsValue: showSystemValueInHUD,
                            action: {
                                enableGradient = true
                            }
                        )
                    }
                    .padding(.vertical, 4)

                    Toggle("Enable glow", isOn: $systemEventIndicatorShadow)

                    Toggle("Show on Lock Screen", isOn: $showHUDOnLockScreen)
                        .disabled(!hudReplacement || !Defaults[.showOnLockScreen])

                    Toggle("Show values in HUD", isOn: $showSystemValueInHUD)
                } header: {
                    SettingsSectionHeader(title: "Styling")
                }

                Section {
                    HUDNotificationToggleRow(
                        title: "Volume",
                        systemImage: "speaker.wave.2.fill",
                        isOn: $showVolumeIndicator
                    )

                    HUDNotificationToggleRow(
                        title: "Brightness",
                        systemImage: "sun.max.fill",
                        isOn: $showBrightnessIndicator
                    )

                    HUDNotificationToggleRow(
                        title: "Keyboard backlight",
                        systemImage: "keyboard.fill",
                        isOn: $showBacklightIndicator
                    )

                    HUDNotificationToggleRow(
                        title: "Caps lock indicator",
                        systemImage: "capslock.fill",
                        isOn: $showCapsLockIndicator
                    )

                    HUDNotificationToggleRow(
                        title: "Input language indicator",
                        systemImage: "globe",
                        isOn: $showInputSourceIndicator
                    )

                    HUDNotificationToggleRow(
                        title: "Focus",
                        systemImage: "moon.fill",
                        isOn: $showFocusIndicator
                    )

                    HUDNotificationToggleRow(
                        title: "Battery",
                        systemImage: "battery.100percent.bolt",
                        isOn: $showPowerStatusNotifications
                    )

                    HUDNotificationToggleRow(
                        title: "Recording",
                        systemImage: "record.circle.fill",
                        isOn: $enableScreenRecordingDetection
                    )

                    HUDNotificationToggleRow(
                        title: "Bluetooth Audio",
                        systemImage: "headphones.over.ear",
                        isOn: $showBluetoothAudioIndicator
                    )

                    if showBluetoothAudioIndicator {
                        HStack(spacing: 8) {
                            HUDBluetoothStyleOptionCard(
                                title: "Animation",
                                isSelected: animateBluetoothAudioIndicator,
                                usesAnimation: true,
                                action: {
                                    animateBluetoothAudioIndicator = true
                                }
                            )

                            HUDBluetoothStyleOptionCard(
                                title: "Icon",
                                isSelected: !animateBluetoothAudioIndicator,
                                usesAnimation: false,
                                action: {
                                    animateBluetoothAudioIndicator = false
                                }
                            )
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    SettingsSectionHeader(title: "Notifications")
                }

                Section {
                    switch cliInstallState {
                    case .bundled:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Install notcherahud to send custom HUD notifications from the terminal.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button("Install Command Line Tool") {
                                do {
                                    try CLIToolManager.install()
                                    cliInstallError = nil
                                    cliInstallState = CLIToolManager.installState()
                                } catch {
                                    cliInstallError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            if let cliInstallError {
                                Text(cliInstallError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    case .installed:
                        Toggle(isOn: $showCLINotifications) {
                            Label("Show notifications from CLI", systemImage: "apple.terminal.fill")
                        }
                    case .unavailable:
                        Text("Command line tool is unavailable in this build.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SettingsSectionHeader(title: "CLI")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            cliInstallState = CLIToolManager.installState()
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

enum CLIToolInstallState: Equatable {
    case bundled
    case installed
    case unavailable
}

enum CLIToolInstallError: LocalizedError {
    case bundledBinaryMissing

    var errorDescription: String? {
        switch self {
        case .bundledBinaryMissing:
            "notcherahud binary is not available in this build"
        }
    }
}

struct CLIToolManager {
    static let executableName = "notcherahud"

    static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static var installedExecutableURL: URL {
        installDirectory.appendingPathComponent(executableName, isDirectory: false)
    }

    static func installState() -> CLIToolInstallState {
        let installedURL = installedExecutableURL
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return .installed
        }

        return bundledExecutableURL() == nil ? .unavailable : .bundled
    }

    static func install() throws {
        guard let sourceURL = bundledExecutableURL() else {
            throw CLIToolInstallError.bundledBinaryMissing
        }

        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let destinationURL = installedExecutableURL
        if FileManager.default.fileExists(atPath: destinationURL.path) || isSymlink(at: destinationURL) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
        try ensureShellPathConfigured()
    }

    private static func bundledExecutableURL() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: executableName, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundledURL.path)
        {
            return bundledURL
        }

        let localBuildURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cli", isDirectory: true)
            .appendingPathComponent("notcherahud", isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)

        if FileManager.default.isExecutableFile(atPath: localBuildURL.path) {
            return localBuildURL
        }

        return nil
    }

    private static func ensureShellPathConfigured() throws {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let configFiles: [URL]

        if shell.hasSuffix("/bash") {
            configFiles = [
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bash_profile", isDirectory: false)
            ]
        } else {
            configFiles = [
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc", isDirectory: false)
            ]
        }

        let exportLine = "export PATH=\"$HOME/.local/bin:$PATH\""

        for fileURL in configFiles {
            let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            guard !existing.contains(exportLine) else { continue }

            let prefix = existing.isEmpty || existing.hasSuffix("\n") ? existing : existing + "\n"
            try (prefix + exportLine + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func isSymlink(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink ?? false
    }
}

private struct HUDNotificationToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct HUDProgressStyleOptionCard: View {
    let title: String
    let isSelected: Bool
    let usesGradient: Bool
    let glowEnabled: Bool
    let showsValue: Bool
    let action: () -> Void

    var body: some View {
        SettingsOptionCard(title: title, isSelected: isSelected, action: action) {
            HUDProgressStylePreview(usesGradient: usesGradient, glowEnabled: glowEnabled, showsValue: showsValue)
        }
    }
}

private struct HUDProgressStylePreview: View {
    let usesGradient: Bool
    let glowEnabled: Bool
    let showsValue: Bool

    private var fillStyle: AnyShapeStyle {
        if usesGradient {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.2)],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            )
        }

        return AnyShapeStyle(Color.white)
    }

    private var glowColor: Color {
        Color.white
    }

    var body: some View {
        HStack(spacing: showsValue ? 4 : 0) {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.tertiary)

                Capsule(style: .continuous)
                    .fill(fillStyle)
                    .frame(width: 34)
                    .shadow(color: glowEnabled ? glowColor : .clear, radius: glowEnabled ? 4 : 0, x: glowEnabled ? 1 : 0)
            }
            .frame(width: 52, height: 6)

            if showsValue {
                Text("60")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .animation(.smooth(duration: 0.18), value: glowEnabled)
        .animation(.smooth(duration: 0.18), value: usesGradient)
        .animation(.smooth(duration: 0.18), value: showsValue)
    }
}

private struct HUDBluetoothStyleOptionCard: View {
    let title: String
    let isSelected: Bool
    let usesAnimation: Bool
    let action: () -> Void

    private let bluetoothIconName = "airpods"
    private let bluetoothAnimationName = "airpods"

    var body: some View {
        SettingsOptionCard(title: title, isSelected: isSelected, action: action) {
            Group {
                if usesAnimation, let url = Bundle.main.url(forResource: bluetoothAnimationName, withExtension: "mov", subdirectory: "BluetoothHUDAnimations") {
                    SettingsBluetoothLoopingVideoIcon(url: url, size: CGSize(width: 22, height: 22))
                } else {
                    Image(systemName: bluetoothIconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
        }
    }
}

private final class SettingsBluetoothLoopingPlayerController {
    private let playbackRate: Float = 1.25

    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.playImmediately(atRate: playbackRate)
    }

    deinit {
        player.pause()
        looper = nil
    }
}

private struct SettingsBluetoothLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)

        context.coordinator.attach(playerLayer: playerLayer, url: url)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var controller: SettingsBluetoothLoopingPlayerController?

        func attach(playerLayer: AVPlayerLayer, url: URL) {
            controller = SettingsBluetoothLoopingPlayerController(url: url)
            playerLayer.player = controller?.player
        }
    }
}
