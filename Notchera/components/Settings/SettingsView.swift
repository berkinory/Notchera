import CryptoKit
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Network
import Sparkle
import Security
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "HUD") {
                    Label("HUDs", systemImage: "dial.medium.fill")
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Clipboard") {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                NavigationLink(value: "Advanced") {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                NavigationLink(value: "AI Usage") {
                    Label("AI Usage", systemImage: "brain")
                }
                NavigationLink(value: "About") {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "HUD":
                    HUD()
                case "Shelf":
                    Shelf()
                case "Clipboard":
                    ClipboardSettings()
                case "Shortcuts":
                    Shortcuts()
                case "Extensions":
                    GeneralSettings()
                case "Advanced":
                    Advanced()
                case "AI Usage":
                    AIUsageSettings()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil
                            )
                        )
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }

    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    @Default(.showEmojis) var showEmojis
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.openNotchOnHover) var openNotchOnHover

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                LaunchAtLogin.Toggle("Launch at login")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil
                    )
                }
                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)

                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil
                    )
                }
                .disabled(showOnAllDisplays)
            } header: {
                Text("System features")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                    Text("Notch height on notch displays")
                ) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                }
                .onChange(of: notchHeightMode) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil
                    )
                }

                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                }
                .onChange(of: nonNotchHeightMode) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil
                    )
                }
            } header: {
                Text("Notch sizing")
            }

            NotchBehaviour()
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .navigationTitle("General")
    }

    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            Defaults.Toggle(key: .trackpadTabSwitch) {
                Text("Switch tabs with trackpad swipe")
            }
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0 ... 1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil
                    )
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct HUD: View {
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
                Text("General")
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
                Text("Indicators")
            } footer: {
                Text("Replace system HUD acts as the master switch. When it is off, no indicator runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!hudReplacement)

        }
        .navigationTitle("HUDs")
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

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @Default(.enableLyrics) var enableLyrics
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                HStack {
                    Stepper(value: $waitInterval, in: 0 ... 10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }

            Section {
                MusicSlotConfigurationView()
                Toggle(isOn: $enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
                .onChange(of: enableLyrics) { _, isEnabled in
                    MusicManager.shared.setLyricsEnabled(isEnabled)
                }
            } header: {
                Text("Media controls")
            } footer: {
                Text("Customize which controls appear in the music player.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Media")
    }

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            MediaControllerType.allCases
        }
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/berkinory/Notchera") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made with 🫶🏻 by the notchera team")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

struct Shelf: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .notchShelf) {
                    Text("Enable shelf")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }

            } header: {
                HStack {
                    Text("General")
                }
            } footer: {
                Text("Shelf only accepts file drops.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Shelf")
    }
}

struct ClipboardSettings: View {
    @Default(.enableClipboardHistory) var enableClipboardHistory
    @Default(.clipboardHistoryRetention) var clipboardHistoryRetention
    @Default(.clipboardHistoryMaxStoredItems) var clipboardHistoryMaxStoredItems

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardHistory) {
                    Text("Enable clipboard history")
                }
            }

            Section {
                Picker("Keep clipboard history for", selection: $clipboardHistoryRetention) {
                    ForEach(ClipboardHistoryRetention.allCases) { retention in
                        Text(retention.rawValue).tag(retention)
                    }
                }
                .onChange(of: clipboardHistoryRetention) { _, _ in
                    ClipboardHistoryManager.shared.pruneExpiredItems()
                }

                Stepper(value: $clipboardHistoryMaxStoredItems, in: 1 ... 100) {
                    HStack {
                        Text("Max stored items")
                        Spacer()
                        Text("\(clipboardHistoryMaxStoredItems)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: clipboardHistoryMaxStoredItems) { _, _ in
                    ClipboardHistoryManager.shared.pruneExpiredItems()
                }
            } footer: {
                Text("Clipboard history stores copied text locally on this Mac. Folders, multi-file copies, and text longer than 6,000 characters are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enableClipboardHistory)

            Section {
                Button(role: .destructive) {
                    ClipboardHistoryManager.shared.clear()
                } label: {
                    Text("Clear clipboard history")
                }
            }
            .disabled(!enableClipboardHistory)
        }
        .navigationTitle("Clipboard")
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .matchAlbumArtColor) {
                    Text("Match album art color")
                }
            } header: {
                Text("Media")
            }
        }
        .navigationTitle("Appearance")
    }
}

struct Advanced: View {
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    @Default(.hideNotchInFullscreen) var hideNotchInFullscreen

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

    var body: some View {
        Form {
            Section {
                HStack {
                    ForEach(icons, id: \.self) { icon in
                        Spacer()
                        VStack {
                            Image(icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .circular)
                                        .strokeBorder(
                                            icon == selectedIcon ? Color.white.opacity(0.35) : .clear,
                                            lineWidth: 2.5
                                        )
                                )

                            Text("Default")
                                .fontWeight(.medium)
                                .font(.caption)
                                .foregroundStyle(icon == selectedIcon ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(icon == selectedIcon ? Color.white.opacity(0.16) : .clear)
                                )
                        }
                        .onTapGesture {
                            withAnimation {
                                selectedIcon = icon
                            }
                            NSApp.applicationIconImage = NSImage(named: icon)
                        }
                        Spacer()
                    }
                }
                .disabled(true)
            } header: {
                HStack {
                    Text("App icon")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                Defaults.Toggle(key: .hideNotchInFullscreen) {
                    Text("Hide notch in fullscreen")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window Behavior")
            }
        }
        .navigationTitle("Advanced")
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Command Palette:", name: .commandPalette)
                KeyboardShortcuts.Recorder("Open Clipboard Manager:", name: .clipboardHistoryPanel)
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
        }
        .navigationTitle("Shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1
            )
        )
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct AIUsageSettings: View {
    @StateObject private var store = AIUsageStore.shared
    @State private var showingAddSheet = false
    @Default(.enableAIUsage) var enableAIUsage
    @Default(.aiUsageShowRemaining) var aiUsageShowRemaining

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAIUsage) {
                    Text("Enable AI usage tab")
                }
                Defaults.Toggle(key: .aiUsageShowRemaining) {
                    Text("Show remaining instead of used")
                }
                .disabled(!enableAIUsage)
            } footer: {
                Text("Claude uses the currently logged-in Claude Code account. Codex supports multiple saved accounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if store.accounts.isEmpty {
                    Text("No accounts added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.accounts) { account in
                        HStack(spacing: 10) {
                            AIUsageProviderIcon(provider: account.provider)
                            Text(account.alias)
                            Spacer()
                            if account.isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button(role: .destructive) {
                                store.removeAccount(id: account.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Delete account")
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                store.removeAccount(id: account.id)
                            }
                        }
                    }
                }
            } header: {
                Text("Accounts")
            }
        }
        .navigationTitle("AI Usage")
        .toolbar {
            Button {
                showingAddSheet = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAIUsageAccountSheet()
        }
    }
}

struct AIUsageDashboardView: View {
    @StateObject private var store = AIUsageStore.shared
    @Default(.aiUsageShowRemaining) var aiUsageShowRemaining

    private let columns = [
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.72))

                    VStack(spacing: 3) {
                        Text("No accounts yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Add Codex or Claude accounts in Settings.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 6)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(store.accounts) { account in
                            AIUsageCard(account: account, showRemaining: aiUsageShowRemaining)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 1)
                    .padding(.bottom, 5)
                }
            }
        }
        .task {
            await store.refreshIfNeeded(force: false)
        }
    }
}

struct AIUsageProviderIcon: View {
    let provider: AIUsageProvider
    var size: CGFloat = 12

    var body: some View {
        switch provider {
        case .codex:
            Image("chatgpt")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size, height: size)
        case .claude:
            Image("claude")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

private struct AIUsageCard: View {
    let account: AIUsageAccount
    let showRemaining: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let snapshot = account.snapshot {
                HStack(alignment: .center, spacing: 5) {
                    AIUsageProviderIcon(provider: account.provider, size: 10)
                    Text(account.alias)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Group {
                        if account.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 10, height: 10)
                    Spacer(minLength: 0)
                    Text(AIUsageMetricRow.resetText(for: snapshot.fiveHour, isWeekly: false))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .multilineTextAlignment(.trailing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    AIUsageMetricRow(
                        title: nil,
                        snapshot: snapshot.fiveHour,
                        showRemaining: showRemaining,
                        isWeekly: false,
                        showReset: false
                    )
                    AIUsageMetricRow(
                        title: "Weekly",
                        snapshot: snapshot.weekly,
                        showRemaining: showRemaining,
                        isWeekly: true,
                        showReset: true
                    )
                }
            } else if let lastError = account.lastError, !lastError.isEmpty {
                HStack(alignment: .center, spacing: 5) {
                    AIUsageProviderIcon(provider: account.provider, size: 10)
                    Text(account.alias)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Group {
                        if account.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 10, height: 10)
                    Spacer(minLength: 0)
                }
                Text(lastError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .center, spacing: 5) {
                    AIUsageProviderIcon(provider: account.provider, size: 10)
                    Text(account.alias)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Group {
                        if account.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 10, height: 10)
                    Spacer(minLength: 0)
                }
                Text("No usage yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct AIUsageMetricRow: View {
    let title: String?
    let snapshot: AIUsageWindowSnapshot
    let showRemaining: Bool
    let isWeekly: Bool
    let showReset: Bool

    static func resetText(for snapshot: AIUsageWindowSnapshot, isWeekly: Bool) -> String {
        if let resetDescription = snapshot.resetDescription, !resetDescription.isEmpty {
            return resetDescription
        }
        guard let resetAt = snapshot.resetAt else {
            return "reset unknown"
        }
        if isWeekly {
            return "resets \(resetAt.formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute()))"
        }
        return "resets \(resetAt.formatted(date: .omitted, time: .shortened))"
    }

    private var displayPercent: Double {
        showRemaining ? snapshot.remainingPercent : snapshot.usedPercent
    }

    private var metricColor: Color {
        let usedPercent = snapshot.usedPercent

        if showRemaining {
            if usedPercent < 60 {
                return .green
            }
            if usedPercent < 85 {
                return .yellow
            }
            return .red
        }

        if usedPercent < 60 {
            return .green
        }
        if usedPercent < 85 {
            return .yellow
        }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showReset {
                HStack(alignment: .center, spacing: 8) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(formattedReset)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(alignment: .center, spacing: 6) {
                ProgressView(value: displayPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(metricColor)
                Text(displayPercent.formattedPercent)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(metricColor)
                    .fixedSize()
            }
        }
    }

    private var formattedReset: String {
        Self.resetText(for: snapshot, isWeekly: isWeekly)
    }
}

private struct AddAIUsageAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIUsageStore.shared
    @StateObject private var loginSession = CodexLoginSession()
    @State private var alias = ""
    @State private var provider: AIUsageProvider = .codex
    @State private var codexAutoCompleteTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add AI Account")
                .font(.title2.weight(.semibold))

            Picker("Provider", selection: $provider) {
                Text("Codex").tag(AIUsageProvider.codex)
                Text("Claude").tag(AIUsageProvider.claude)
            }
            .pickerStyle(.segmented)

            TextField("Alias", text: $alias)
                .textFieldStyle(.roundedBorder)

            if provider == .codex {
                if let authorizationURL = loginSession.authorizationURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Browser sign-in opens automatically. If callback does not complete, paste the full redirect URL or code below.")
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(authorizationURL.absoluteString)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Login Page") {
                                NSWorkspace.shared.open(authorizationURL)
                            }
                        }

                        TextField("Paste redirect URL or authorization code", text: $loginSession.manualInput)
                            .textFieldStyle(.roundedBorder)

                        Text("Waiting for approval in your browser…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Sign in with your ChatGPT account.", systemImage: "person.crop.circle.badge.checkmark")
                        Label("No API key required.", systemImage: "key.slash")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Uses the currently logged-in Claude Code account.", systemImage: "terminal")
                    Label("Requires Claude Code CLI to be installed and authenticated.", systemImage: "checkmark.shield")
                    Text("Run `claude auth login` first. Notchera will read `claude auth status` and `/usage` from the CLI.")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let errorMessage = loginSession.errorMessage, provider == .codex {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    loginSession.cancel()
                    dismiss()
                }
                Button(provider == .codex ? (loginSession.authorizationURL == nil ? "Connect" : "Finish") : "Add") {
                    Task {
                        if provider == .codex {
                            if loginSession.authorizationURL == nil {
                                await startLogin()
                            } else {
                                await finishLogin()
                            }
                        } else {
                            await addClaude()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (provider == .codex && loginSession.isBusy))
            }
        }
        .padding(20)
        .frame(width: 520)
        .overlay(alignment: .topTrailing) {
            if loginSession.isBusy && provider == .codex {
                ProgressView()
                    .controlSize(.small)
                    .padding(16)
            }
        }
        .onDisappear {
            codexAutoCompleteTask?.cancel()
            codexAutoCompleteTask = nil
        }
    }

    @MainActor
    private func startLogin() async {
        do {
            try await loginSession.start()
            codexAutoCompleteTask?.cancel()
            codexAutoCompleteTask = Task {
                do {
                    let credentials = try await loginSession.completeFromCallbackOnly()
                    await store.addAccount(
                        alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
                        provider: .codex,
                        credentials: .codex(credentials)
                    )
                    await MainActor.run {
                        dismiss()
                    }
                } catch is CancellationError {
                } catch {
                    await MainActor.run {
                        loginSession.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            loginSession.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func finishLogin() async {
        do {
            codexAutoCompleteTask?.cancel()
            codexAutoCompleteTask = nil
            let credentials = try await loginSession.complete()
            await store.addAccount(
                alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: .codex,
                credentials: .codex(credentials)
            )
            dismiss()
        } catch {
            loginSession.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addClaude() async {
        await store.addAccount(
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: .claude,
            credentials: .claude
        )
        dismiss()
    }
}

enum AIUsageProvider: String, Codable, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }
}

private enum AIUsageCredentials {
    case claude
    case codex(CodexStoredCredentials)
}

private struct CodexStoredCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountId: String
}

private struct AIUsageWindowSnapshot: Codable {
    var usedPercent: Double
    var remainingPercent: Double
    var resetAt: Date?
    var resetDescription: String?
}

private struct AIUsageSnapshot: Codable {
    var fiveHour: AIUsageWindowSnapshot
    var weekly: AIUsageWindowSnapshot
    var fetchedAt: Date
}

private struct AIUsageAccount: Identifiable, Codable {
    var id: UUID
    var alias: String
    var provider: AIUsageProvider
    var snapshot: AIUsageSnapshot?
    var lastError: String?
    var isRefreshing: Bool = false
}

@MainActor
private final class AIUsageStore: ObservableObject {
    static let shared = AIUsageStore()

    @Published private(set) var accounts: [AIUsageAccount] = []

    private let credentialStore = AIUsageCredentialStore.shared
    private let service = AIUsageService()
    private let fileURL: URL
    private let cacheTTL: TimeInterval = 5 * 60

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Notchera", isDirectory: true)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = baseDirectory.appendingPathComponent("ai-usage-accounts.json")
        load()
    }

    func addAccount(alias: String, provider: AIUsageProvider, credentials: AIUsageCredentials) async {
        let account = AIUsageAccount(
            id: UUID(),
            alias: alias,
            provider: provider,
            snapshot: nil,
            lastError: nil
        )

        do {
            try credentialStore.store(credentials, for: account)
            accounts.append(account)
            save()
            await refreshAccount(id: account.id, force: true)
        } catch {
            print("[AIUsageStore] Failed to store credentials: \(error)")
        }
    }

    func removeAccount(id: UUID) {
        if let account = accounts.first(where: { $0.id == id }) {
            try? credentialStore.removeCredentials(for: account)
        }
        accounts.removeAll { $0.id == id }
        save()
    }

    func refreshIfNeeded(force: Bool) async {
        for account in accounts {
            guard force || shouldRefresh(account) else {
                continue
            }
            await refreshAccount(id: account.id, force: force)
        }
    }

    private func shouldRefresh(_ account: AIUsageAccount) -> Bool {
        guard let fetchedAt = account.snapshot?.fetchedAt else {
            return true
        }

        return Date().timeIntervalSince(fetchedAt) >= cacheTTL
    }

    private func refreshAccount(id: UUID, force: Bool) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        if accounts[index].isRefreshing {
            return
        }

        accounts[index].isRefreshing = true
        accounts[index].lastError = nil

        do {
            let refreshed = try await service.refreshAccount(accounts[index], force: force)
            accounts[index] = refreshed
        } catch {
            accounts[index].lastError = error.localizedDescription
            accounts[index].isRefreshing = false
        }

        save()
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                accounts = []
                return
            }

            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            accounts = try decoder.decode([AIUsageAccount].self, from: data).filter { account in
                guard account.provider == .codex else { return true }
                return (try? credentialStore.credentials(for: account)) != nil
            }
        } catch {
            accounts = []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(accounts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[AIUsageStore] Failed to save accounts: \(error)")
        }
    }
}

private actor AIUsageService {
    private let credentialStore = AIUsageCredentialStore.shared
    private let codexAuthClient = CodexAuthClient()
    private let codexUsageClient = CodexUsageClient()
    private let claudeCLI = ClaudeCLIClient()

    func refreshAccount(_ account: AIUsageAccount, force _: Bool) async throws -> AIUsageAccount {
        var refreshed = account

        switch account.provider {
        case .claude:
            refreshed.snapshot = try await claudeCLI.fetchUsage()
        case .codex:
            guard case let .codex(credentials) = try credentialStore.credentials(for: account) else {
                throw AIUsageError.requestFailed("Missing Codex credentials")
            }
            let updatedCredentials = try await codexAuthClient.ensureValidCredentials(credentials)
            try credentialStore.store(.codex(updatedCredentials), for: account)
            refreshed.snapshot = try await codexUsageClient.fetchUsage(credentials: updatedCredentials)
        }

        refreshed.lastError = nil
        refreshed.isRefreshing = false
        return refreshed
    }
}

private final class AIUsageCredentialStore {
    static let shared = AIUsageCredentialStore()

    private let service = "notchera.ai-usage"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func store(_ credentials: AIUsageCredentials, for account: AIUsageAccount) throws {
        switch credentials {
        case .claude:
            try removeCredentials(for: account)
        case let .codex(storedCredentials):
            let data = try encoder.encode(storedCredentials)
            let query = baseQuery(for: account)

            SecItemDelete(query as CFDictionary)

            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw AIUsageError.requestFailed("Failed to save credentials (\(status))")
            }
        }
    }

    func credentials(for account: AIUsageAccount) throws -> AIUsageCredentials {
        switch account.provider {
        case .claude:
            return .claude
        case .codex:
            var query = baseQuery(for: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status != errSecItemNotFound else {
                throw AIUsageError.requestFailed("Missing Codex credentials")
            }

            guard status == errSecSuccess,
                  let data = result as? Data
            else {
                throw AIUsageError.requestFailed("Failed to load credentials (\(status))")
            }

            return .codex(try decoder.decode(CodexStoredCredentials.self, from: data))
        }
    }

    func removeCredentials(for account: AIUsageAccount) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIUsageError.requestFailed("Failed to remove credentials (\(status))")
        }
    }

    private func baseQuery(for account: AIUsageAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account.provider.rawValue).\(account.id.uuidString)"
        ]
    }
}

private actor CodexAuthClient {
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let expiryLeeway: TimeInterval = 5 * 60
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func ensureValidCredentials(_ credentials: CodexStoredCredentials) async throws -> CodexStoredCredentials {
        guard Date().addingTimeInterval(expiryLeeway) >= credentials.expiresAt else {
            return credentials
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
            URLQueryItem(name: "client_id", value: clientID),
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let tokenResponse = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        guard let accessToken = tokenResponse.accessToken,
              let refreshToken = tokenResponse.refreshToken,
              let expiresIn = tokenResponse.expiresIn
        else {
            throw AIUsageError.invalidTokenResponse
        }

        let accountId = try CodexJWTDecoder.accountID(from: accessToken)
        return CodexStoredCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            accountId: accountId
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }
}

private actor CodexUsageClient {
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: configuration)
    }

    func fetchUsage(credentials: CodexStoredCredentials) async throws -> AIUsageSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let usageResponse = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        return usageResponse.snapshot
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }
}

private struct CodexUsageResponse: Decodable {
    let rateLimit: CodexUsageRateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    var snapshot: AIUsageSnapshot {
        AIUsageSnapshot(
            fiveHour: rateLimit?.primaryWindow?.snapshot ?? .empty,
            weekly: rateLimit?.secondaryWindow?.snapshot ?? .empty,
            fetchedAt: Date()
        )
    }
}

private struct CodexUsageRateLimit: Decodable {
    let primaryWindow: CodexUsageWindow?
    let secondaryWindow: CodexUsageWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexUsageWindow: Decodable {
    let usedPercent: Double?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }

    var snapshot: AIUsageWindowSnapshot {
        let used = max(0, min(100, usedPercent ?? 0))
        return AIUsageWindowSnapshot(
            usedPercent: used,
            remainingPercent: max(0, 100 - used),
            resetAt: resetAt.map { Date(timeIntervalSince1970: $0) },
            resetDescription: nil
        )
    }
}

private struct CodexTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct CodexOAuthCredentials {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountId: String
}

private struct CodexAuthorizationState {
    var verifier: String
    var state: String
    var authorizationURL: URL
    var callbackServer: CodexCallbackServer
}

@MainActor
private final class CodexLoginSession: ObservableObject {
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var authorizationURL: URL?
    @Published var manualInput = ""

    private let client = CodexBrowserAuthClient()
    private var authState: CodexAuthorizationState?

    func start() async throws {
        cancel()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let authState = try await client.startAuthorization()
        self.authState = authState
        self.authorizationURL = authState.authorizationURL
        NSWorkspace.shared.open(authState.authorizationURL)
    }

    func complete() async throws -> CodexStoredCredentials {
        try await finishLogin(manualInput: manualInput)
    }

    func completeFromCallbackOnly() async throws -> CodexStoredCredentials {
        try await finishLogin(manualInput: "")
    }

    private func finishLogin(manualInput: String) async throws -> CodexStoredCredentials {
        guard let authState else {
            throw AIUsageError.requestFailed("Login has not started yet")
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let credentials = try await client.completeAuthorization(state: authState, manualInput: manualInput)
        cancel()
        return CodexStoredCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            accountId: credentials.accountId
        )
    }

    func cancel() {
        authState?.callbackServer.cancel()
        authState = nil
        authorizationURL = nil
        manualInput = ""
    }
}

private actor CodexBrowserAuthClient {
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let redirectURL = URL(string: "http://localhost:1455/auth/callback")!
    private let scope = "openid profile email offline_access"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startAuthorization() async throws -> CodexAuthorizationState {
        let verifier = Self.makeCodeVerifier()
        let challenge = try Self.makeCodeChallenge(verifier: verifier)
        let state = Self.makeState()
        let callbackServer = try CodexCallbackServer(expectedState: state)

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "notchera")
        ]

        guard let authorizationURL = components?.url else {
            callbackServer.cancel()
            throw AIUsageError.requestFailed("Failed to build Codex authorization URL")
        }

        return CodexAuthorizationState(
            verifier: verifier,
            state: state,
            authorizationURL: authorizationURL,
            callbackServer: callbackServer
        )
    }

    func completeAuthorization(state: CodexAuthorizationState, manualInput: String) async throws -> CodexOAuthCredentials {
        let code = try await state.callbackServer.waitForCode(manualInput: manualInput)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: state.verifier),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString)
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let tokenResponse = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        guard let accessToken = tokenResponse.accessToken,
              let refreshToken = tokenResponse.refreshToken,
              let expiresIn = tokenResponse.expiresIn else {
            throw AIUsageError.invalidTokenResponse
        }

        let accountId = try CodexJWTDecoder.accountID(from: accessToken)
        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            accountId: accountId
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }

    private static func makeState() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func makeCodeVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(verifier: String) throws -> String {
        guard let data = verifier.data(using: .utf8) else {
            throw AIUsageError.requestFailed("Failed to encode PKCE verifier")
        }
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
}

private final class CodexCallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.notchera.codex-callback")
    private var resultContinuation: CheckedContinuation<String, Error>?
    private var isFinished = false

    init(expectedState: String) throws {
        self.expectedState = expectedState
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 1455)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    func waitForCode(manualInput: String) async throws -> String {
        if let code = Self.extractCode(from: manualInput, expectedState: expectedState) {
            finish(.success(code))
            return code
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.resultContinuation = continuation
        }
    }

    func cancel() {
        finish(.failure(AIUsageError.requestFailed("Login cancelled")))
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                return
            }
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? request
            guard let code = Self.extractCode(from: firstLine, expectedState: self.expectedState) else {
                return
            }
            self.respond(connection: connection)
            self.finish(.success(code))
        }
    }

    private func respond(connection: NWConnection) {
        let body = """
<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Notchera</title>
<style>
:root {
    color-scheme: dark;
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
}
* {
    box-sizing: border-box;
}
html, body {
    margin: 0;
    min-height: 100%;
    background:
        radial-gradient(circle at top, rgba(255,255,255,0.12), transparent 36%),
        linear-gradient(180deg, #151517 0%, #0b0b0c 100%);
    color: #f5f5f7;
}
body {
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 32px;
}
.card {
    width: min(100%, 460px);
    padding: 32px 30px;
    border-radius: 24px;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.1);
    box-shadow: 0 24px 80px rgba(0,0,0,0.38);
    backdrop-filter: blur(18px);
    text-align: center;
}
.badge {
    width: 56px;
    height: 56px;
    margin: 0 auto 18px;
    border-radius: 18px;
    display: grid;
    place-items: center;
    font-size: 24px;
    background: linear-gradient(180deg, rgba(255,255,255,0.16), rgba(255,255,255,0.08));
    border: 1px solid rgba(255,255,255,0.12);
}
h1 {
    margin: 0;
    font-size: 28px;
    font-weight: 600;
    letter-spacing: -0.03em;
}
p {
    margin: 10px 0 0;
    font-size: 15px;
    line-height: 1.5;
    color: rgba(245,245,247,0.72);
}
.secondary {
    margin-top: 18px;
    font-size: 13px;
    color: rgba(245,245,247,0.48);
}
</style>
</head>
<body>
<div class=\"card\">
    <div class=\"badge\">✓</div>
    <h1>notchera</h1>
    <p>successful. your codex account is now connected.</p>
    <p class=\"secondary\">you can return to the app now.</p>
</div>
<script>
window.close();
</script>
</body>
</html>
"""
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func finish(_ result: Result<String, Error>) {
        guard !isFinished else { return }
        isFinished = true
        listener.cancel()
        resultContinuation?.resume(with: result)
        resultContinuation = nil
    }

    private static func extractCode(from input: String, expectedState: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let raw: String
        if trimmed.hasPrefix("GET "), let pathComponent = trimmed.split(separator: " ").dropFirst().first {
            raw = "http://localhost\(pathComponent)"
        } else {
            raw = trimmed
        }

        guard let url = URL(string: raw), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let state = components.queryItems?.first(where: { $0.name == "state" })?.value, state != expectedState {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }
}

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
    let authMethod: String?
    let apiProvider: String?
    let email: String?
    let orgId: String?
    let orgName: String?
    let subscriptionType: String?
}

private actor ClaudeCLIClient {
    func fetchUsage() async throws -> AIUsageSnapshot {
        let workingDirectory = try isolatedWorkingDirectory()

        let statusOutput = try runCommand(["auth", "status"], currentDirectoryURL: workingDirectory)
        let statusData = Data(statusOutput.utf8)
        let status = try JSONDecoder().decode(ClaudeAuthStatus.self, from: statusData)

        guard status.loggedIn else {
            throw AIUsageError.requestFailed("Claude Code is not logged in")
        }

        let usageOutput = try runPTYUsage(currentDirectoryURL: workingDirectory)
        return try ClaudeUsageParser.parse(usageOutput)
    }

    private func isolatedWorkingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchera-claude-usage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func runCommand(_ arguments: [String], currentDirectoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude"] + arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw AIUsageError.requestFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func runPTYUsage(currentDirectoryURL: URL) throws -> String {
        let script = #"""
import os, pty, subprocess, select, time, sys
cwd = sys.argv[1]
master, slave = pty.openpty()
proc = subprocess.Popen(['claude'], stdin=slave, stdout=slave, stderr=slave, text=False, cwd=cwd)
os.close(slave)
out = b''
def drain(seconds):
    end = time.time() + seconds
    global out
    while time.time() < end:
        r,_,_ = select.select([master], [], [], 0.2)
        if master in r:
            try:
                data = os.read(master, 4096)
            except OSError:
                return
            if not data:
                return
            out += data
for _ in range(25):
    drain(0.25)
    if b'Claude Code' in out or b'/help' in out or b'Welcome back' in out or '❯'.encode() in out:
        break
os.write(master, b'/usage\r')
for _ in range(24):
    drain(0.25)
    low = out.lower()
    if b'current session' in low and b'current week' in low:
        break
os.write(master, b'\x03')
drain(1.0)
try:
    proc.terminate()
except Exception:
    pass
sys.stdout.write(out.decode('utf-8', 'ignore'))
"""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, currentDirectoryURL.path]
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        guard !output.isEmpty else {
            throw AIUsageError.requestFailed("Failed to read Claude Code usage")
        }

        return output
    }
}

private enum ClaudeUsageParser {
    static func parse(_ output: String) throws -> AIUsageSnapshot {
        let cleaned = output.replacingOccurrences(of: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        let fiveHour = try parseSection(named: "Current session", in: cleaned)
        let weekly = try parseSection(named: "Current week", in: cleaned)
        return AIUsageSnapshot(fiveHour: fiveHour, weekly: weekly, fetchedAt: Date())
    }

    private static func parseSection(named name: String, in text: String) throws -> AIUsageWindowSnapshot {
        let compactSource = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let compactName = name.replacingOccurrences(of: " ", with: "")

        guard let startRange = compactSource.range(of: compactName) else {
            throw AIUsageError.requestFailed("Could not parse Claude usage section: \(name)")
        }

        let remainingText = String(compactSource[startRange.lowerBound...])
        let sectionBody: String
        if let nextRange = remainingText.dropFirst().range(of: "Current") {
            sectionBody = String(remainingText[..<nextRange.lowerBound])
        } else {
            sectionBody = remainingText
        }

        let usedPercent = parseCompactPercent(from: sectionBody)
        let resetDescription = parseCompactReset(from: sectionBody)
        return AIUsageWindowSnapshot(
            usedPercent: usedPercent,
            remainingPercent: max(0, 100 - usedPercent),
            resetAt: nil,
            resetDescription: resetDescription
        )
    }

    private static func parseCompactPercent(from text: String) -> Double {
        let regex = try? NSRegularExpression(pattern: #"(\d+)%used"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]) else {
            return 0
        }
        return value
    }

    private static func parseCompactReset(from text: String) -> String {
        guard let resetRange = text.range(of: "Rese") else {
            return "reset unknown"
        }
        var value = String(text[resetRange.lowerBound...])
        value = value.replacingOccurrences(of: #"^Reses?|^Resets"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\d+%used.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"What'?scontributing.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"Approximate,.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"Scanninglocalsessions.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"Extrausage.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(Europe/Istanbul)", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let weeklyMatch = value.range(of: #"([A-Za-z]{3})(\d{1,2})at([^A-Z]+(?:am|pm))"#, options: .regularExpression) {
            let matched = String(value[weeklyMatch])
            let regex = try? NSRegularExpression(pattern: #"([A-Za-z]{3})(\d{1,2})at([^A-Z]+(?:am|pm))"#)
            let nsRange = NSRange(matched.startIndex..., in: matched)
            if let match = regex?.firstMatch(in: matched, range: nsRange),
               let monthRange = Range(match.range(at: 1), in: matched),
               let dayRange = Range(match.range(at: 2), in: matched),
               let timeRange = Range(match.range(at: 3), in: matched) {
                let month = monthNumber(String(matched[monthRange]))
                let day = String(matched[dayRange]).leftPadding(toLength: 2, withPad: "0")
                let time = String(matched[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return "resets \(day)/\(month) \(time)"
            }
        }

        if let currentMatch = value.range(of: #"([0-9]{1,2}(?::[0-9]{2})?(?:am|pm))"#, options: .regularExpression) {
            return "resets \(String(value[currentMatch]))"
        }

        if !value.isEmpty {
            return "resets \(value)"
        }

        return "reset unknown"
    }

    private static func monthNumber(_ month: String) -> String {
        switch month.lowercased() {
        case "jan": return "01"
        case "feb": return "02"
        case "mar": return "03"
        case "apr": return "04"
        case "may": return "05"
        case "jun": return "06"
        case "jul": return "07"
        case "aug": return "08"
        case "sep": return "09"
        case "oct": return "10"
        case "nov": return "11"
        case "dec": return "12"
        default: return "--"
        }
    }
}

private enum CodexJWTDecoder {
    static func accountID(from accessToken: String) throws -> String {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let auth = payload["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String,
              !accountId.isEmpty
        else {
            throw AIUsageError.requestFailed("Failed to extract account ID")
        }

        return accountId
    }
}

private enum AIUsageError: LocalizedError {
    case invalidResponse
    case invalidTokenResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidTokenResponse:
            return "Server returned an incomplete token response"
        case let .requestFailed(message):
            return message
        }
    }
}

private extension AIUsageWindowSnapshot {
    static let empty = AIUsageWindowSnapshot(usedPercent: 0, remainingPercent: 100, resetAt: nil, resetDescription: nil)
}

private extension Double {
    var formattedPercent: String {
        String(format: "%.0f%%", self)
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        if count >= toLength {
            return self
        }
        return String(repeating: String(character), count: toLength - count) + self
    }
}

private func formURLEncodedData(_ items: [URLQueryItem]) -> Data? {
    var components = URLComponents()
    components.queryItems = items
    return components.percentEncodedQuery?.data(using: .utf8)
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#Preview {
    HUD()
}
