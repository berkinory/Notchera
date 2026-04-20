import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
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

                Stepper(value: $clipboardHistoryMaxStoredItems, in: 1 ... 25) {
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
                Text("Clipboard history stores copied text locally on this Mac. Folders, multi-file copies, and very large text are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Track Codex usage windows across multiple accounts.")
                            .font(.headline)
                        Text("Notchera stores the minimum credential set locally and refreshes usage automatically when cached data becomes stale.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }

            if store.accounts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No accounts yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add a Codex account to see its 5h and weekly usage windows.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section {
                    ForEach(store.accounts) { account in
                        AIUsageAccountRow(account: account)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    store.removeAccount(id: account.id)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.removeAccount(id: account.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Accounts")
                }
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
        .task {
            await store.refreshIfNeeded(force: false)
        }
    }
}

private struct AIUsageAccountRow: View {
    let account: AIUsageAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.alias)
                        .font(.headline)
                    Text(account.provider.displayName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let snapshot = account.snapshot {
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if account.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let snapshot = account.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    AIUsageWindowRow(
                        title: "Current Period",
                        usedPercent: snapshot.fiveHour.usedPercent,
                        remainingPercent: snapshot.fiveHour.remainingPercent,
                        resetAt: snapshot.fiveHour.resetAt,
                        resetDescription: snapshot.fiveHour.resetDescription
                    )
                    AIUsageWindowRow(
                        title: "Weekly",
                        usedPercent: snapshot.weekly.usedPercent,
                        remainingPercent: snapshot.weekly.remainingPercent,
                        resetAt: snapshot.weekly.resetAt,
                        resetDescription: snapshot.weekly.resetDescription
                    )
                }
            } else if let lastError = account.lastError, !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(account.isRefreshing ? "Refreshing usage…" : "Usage not available yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AIUsageWindowRow: View {
    let title: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Date?
    let resetDescription: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("used \(usedPercent.formattedPercent) · left \(remainingPercent.formattedPercent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ProgressView(value: usedPercent, total: 100)
                    .progressViewStyle(.linear)
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 140, alignment: .trailing)
            }
        }
    }

    private var resetText: String {
        if let resetDescription, !resetDescription.isEmpty {
            return resetDescription
        }
        guard let resetAt else {
            return "reset unknown"
        }

        return "resets \(resetAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct AddAIUsageAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIUsageStore.shared
    @StateObject private var loginSession = CodexLoginSession()
    @State private var alias = ""
    @State private var provider: AIUsageProvider = .codex

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
                if let deviceCode = loginSession.deviceCode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open the verification page and enter this one-time code.")
                            .foregroundStyle(.secondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Verification code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(deviceCode.userCode)
                                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button("Open Login Page") {
                                NSWorkspace.shared.open(deviceCode.verificationURL)
                            }
                        }

                        Text(deviceCode.verificationURL.absoluteString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)

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
                Button(provider == .codex ? (loginSession.deviceCode == nil ? "Connect" : "Finish") : "Add") {
                    Task {
                        if provider == .codex {
                            if loginSession.deviceCode == nil {
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
    }

    @MainActor
    private func startLogin() async {
        do {
            try await loginSession.start()
        } catch {
            loginSession.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func finishLogin() async {
        do {
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

private enum AIUsageProvider: String, Codable, CaseIterable {
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

private enum AIUsageCredentials: Codable {
    case claude
    case codex(CodexStoredCredentials)

    enum CodingKeys: String, CodingKey {
        case type
        case codex
    }

    enum CredentialType: String, Codable {
        case claude
        case codex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CredentialType.self, forKey: .type)
        switch type {
        case .claude:
            self = .claude
        case .codex:
            self = .codex(try container.decode(CodexStoredCredentials.self, forKey: .codex))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .claude:
            try container.encode(CredentialType.claude, forKey: .type)
        case let .codex(credentials):
            try container.encode(CredentialType.codex, forKey: .type)
            try container.encode(credentials, forKey: .codex)
        }
    }
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
    var credentials: AIUsageCredentials
    var snapshot: AIUsageSnapshot?
    var lastError: String?
    var isRefreshing: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case alias
        case provider
        case credentials
        case snapshot
        case lastError
    }
}

@MainActor
private final class AIUsageStore: ObservableObject {
    static let shared = AIUsageStore()

    @Published private(set) var accounts: [AIUsageAccount] = []

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
            credentials: credentials,
            snapshot: nil,
            lastError: nil
        )
        accounts.append(account)
        save()
        await refreshAccount(id: account.id, force: true)
    }

    func removeAccount(id: UUID) {
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
            accounts = try decoder.decode([AIUsageAccount].self, from: data)
        } catch {
            accounts = []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(accounts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[AIUsageStore] Failed to save accounts: \(error)")
        }
    }
}

private actor AIUsageService {
    private let codexAuthClient = CodexAuthClient()
    private let codexUsageClient = CodexUsageClient()
    private let claudeCLI = ClaudeCLIClient()

    func refreshAccount(_ account: AIUsageAccount, force _: Bool) async throws -> AIUsageAccount {
        var refreshed = account
        switch account.credentials {
        case .claude:
            refreshed.snapshot = try await claudeCLI.fetchUsage()
        case let .codex(credentials):
            let updatedCredentials = try await codexAuthClient.ensureValidCredentials(credentials)
            refreshed.credentials = .codex(updatedCredentials)
            refreshed.snapshot = try await codexUsageClient.fetchUsage(credentials: updatedCredentials)
        }
        refreshed.lastError = nil
        refreshed.isRefreshing = false
        return refreshed
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

private struct CodexDeviceCode {
    var verificationURL: URL
    var userCode: String
    var deviceAuthID: String
    var interval: TimeInterval
}

private struct CodexOAuthCredentials {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountId: String
}

@MainActor
private final class CodexLoginSession: ObservableObject {
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var deviceCode: CodexDeviceCode?

    private let client = CodexDeviceAuthClient()

    func start() async throws {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let deviceCode = try await client.requestDeviceCode()
        self.deviceCode = deviceCode
        NSWorkspace.shared.open(deviceCode.verificationURL)
    }

    func complete() async throws -> CodexStoredCredentials {
        guard let deviceCode else {
            throw AIUsageError.requestFailed("Login has not started yet")
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let credentials = try await client.completeLogin(deviceCode: deviceCode)
        self.deviceCode = nil
        return CodexStoredCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            accountId: credentials.accountId
        )
    }

    func cancel() {
        deviceCode = nil
    }
}

private actor CodexDeviceAuthClient {
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let issuer = URL(string: "https://auth.openai.com")!
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let redirectURL = URL(string: "https://auth.openai.com/deviceauth/callback")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceCode() async throws -> CodexDeviceCode {
        var request = URLRequest(url: issuer.appending(path: "/api/accounts/deviceauth/usercode"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CodexDeviceCodeRequest(clientID: clientID))

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(CodexDeviceCodeResponse.self, from: data)
        return CodexDeviceCode(
            verificationURL: issuer.appending(path: "/codex/device"),
            userCode: payload.userCode,
            deviceAuthID: payload.deviceAuthID,
            interval: payload.interval
        )
    }

    func completeLogin(deviceCode: CodexDeviceCode) async throws -> CodexOAuthCredentials {
        let codeResponse = try await pollForAuthorizationCode(deviceCode: deviceCode)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: codeResponse.authorizationCode),
            URLQueryItem(name: "code_verifier", value: codeResponse.codeVerifier),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
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
        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            accountId: accountId
        )
    }

    private func pollForAuthorizationCode(deviceCode: CodexDeviceCode) async throws -> CodexDeviceTokenPollSuccess {
        let deadline = Date().addingTimeInterval(15 * 60)
        let interval = max(1, deviceCode.interval)

        while Date() < deadline {
            var request = URLRequest(url: issuer.appending(path: "/api/accounts/deviceauth/token"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                CodexDeviceTokenPollRequest(
                    deviceAuthID: deviceCode.deviceAuthID,
                    userCode: deviceCode.userCode
                )
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIUsageError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                return try JSONDecoder().decode(CodexDeviceTokenPollSuccess.self, from: data)
            case 404:
                try await Task.sleep(for: .seconds(interval))
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIUsageError.requestFailed(message)
            }
        }

        throw AIUsageError.requestFailed("Device login timed out")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw AIUsageError.requestFailed("Device code login is not enabled for this account yet")
            }
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }
}

private struct CodexDeviceCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct CodexDeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        userCode = try container.decode(String.self, forKey: .userCode)
        if let rawString = try? container.decode(String.self, forKey: .interval),
           let parsed = TimeInterval(rawString) {
            interval = parsed
        } else {
            interval = try container.decode(TimeInterval.self, forKey: .interval)
        }
    }
}

private struct CodexDeviceTokenPollRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

private struct CodexDeviceTokenPollSuccess: Decodable {
    let authorizationCode: String
    let codeChallenge: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeChallenge = "code_challenge"
        case codeVerifier = "code_verifier"
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
        guard let startRange = text.range(of: name) else {
            throw AIUsageError.requestFailed("Could not parse Claude usage section: \(name)")
        }
        let suffix = String(text[startRange.lowerBound...])
        let usedPercent = parsePercent(from: suffix)
        let resetDescription = parseReset(from: suffix)
        return AIUsageWindowSnapshot(
            usedPercent: usedPercent,
            remainingPercent: max(0, 100 - usedPercent),
            resetAt: nil,
            resetDescription: resetDescription
        )
    }

    private static func parsePercent(from text: String) -> Double {
        let regex = try? NSRegularExpression(pattern: #"(\d+)%\s+used"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]) else {
            return 0
        }
        return value
    }

    private static func parseReset(from text: String) -> String {
        let regex = try? NSRegularExpression(pattern: #"Resets\s+([^\n\r]+)"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return "reset unknown"
        }
        return "resets " + text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
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

}

#Preview {
    HUD()
}
