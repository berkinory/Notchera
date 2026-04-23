import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "general"
    let updaterController: SPUStandardUpdaterController?

    private let sections: [SettingsSidebarSection] = [
        SettingsSidebarSection(
            title: "",
            items: [
                SettingsSidebarItem(id: "general", title: "General", icon: "gear")
            ]
        ),
        SettingsSidebarSection(
            title: "Notch",
            items: [
                SettingsSidebarItem(id: "media", title: "Media", icon: "play.laptopcomputer"),
                SettingsSidebarItem(id: "notifications", title: "Notifications", icon: "dial.medium.fill"),
                SettingsSidebarItem(id: "shelf", title: "File Shelf", icon: "books.vertical"),
                SettingsSidebarItem(id: "launcher", title: "Command Launcher", icon: "command"),
                SettingsSidebarItem(id: "clipboard", title: "Clipboard History", icon: "doc.on.clipboard"),
                SettingsSidebarItem(id: "aiUsage", title: "AI Usage", icon: "brain"),
                SettingsSidebarItem(id: "shortcuts", title: "Shortcuts", icon: "keyboard")
            ]
        ),
        SettingsSidebarSection(
            title: "Application",
            items: [
                SettingsSidebarItem(id: "about", title: "About", icon: "info.circle")
            ]
        )
    ]

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    private var selectedItem: SettingsSidebarItem {
        sections
            .flatMap(\.items)
            .first(where: { $0.id == selectedTab })
            ?? sections[0].items[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sharedBackground)
        .toolbar(removing: .sidebarToggle)
        .ignoresSafeArea(.container, edges: .top)
        .formStyle(.grouped)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if !section.displayTitle.isEmpty {
                        Text(section.displayTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.68))
                            .padding(.horizontal, 8)
                    }

                    VStack(spacing: 6) {
                        ForEach(section.items) { item in
                            SettingsSidebarButton(
                                item: item,
                                isSelected: item.id == selectedTab,
                                onClick: {
                                    selectedTab = item.id
                                }
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            QuitAppSidebarButton()
        }
        .padding(.horizontal, 10)
        .padding(.top, 42)
        .padding(.bottom, 10)
        .frame(width: 184, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: selectedItem.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedItem.iconColor)
                    .frame(width: 15, height: 15)
                    .padding(4)
                    .background(iconChipBackground(color: selectedItem.iconColor))

                Text(selectedItem.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.88))

                Spacer()
            }
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            detailContent
                .scrollContentBackground(.hidden)
                .background(sharedBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case "general":
            SettingsGeneralView()
        case "media":
            SettingsMediaView()
        case "notifications":
            HUDSettingsView()
        case "shelf":
            ShelfSettingsView()
        case "launcher":
            SettingsCommandLauncherView()
        case "clipboard":
            ClipboardSettingsView()
        case "aiUsage":
            AIUsageSettingsView()
        case "shortcuts":
            ShortcutsSettingsView()
        case "about":
            if let controller = updaterController {
                AboutSettingsView(updaterController: controller)
            } else {
                AboutSettingsView(
                    updaterController: SPUStandardUpdaterController(
                        startingUpdater: false,
                        updaterDelegate: nil,
                        userDriverDelegate: nil
                    )
                )
            }
        default:
            SettingsGeneralView()
        }
    }

    private var sharedBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }

    private func iconChipBackground(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 0.8)
            }
    }
}

private struct SettingsSidebarSection: Identifiable {
    let title: String
    let items: [SettingsSidebarItem]

    var id: String { title + items.map(\.id).joined() }

    var displayTitle: String { title }
}

private struct SettingsSidebarItem: Identifiable {
    let id: String
    let title: String
    let icon: String

    var iconColor: Color {
        switch id {
        case "general":
            Color(red: 0.62, green: 0.76, blue: 1)
        case "media":
            Color(red: 0.58, green: 0.86, blue: 0.72)
        case "notifications":
            Color(red: 1, green: 0.66, blue: 0.5)
        case "shelf":
            Color(red: 0.84, green: 0.76, blue: 1)
        case "launcher":
            Color(red: 0.98, green: 0.82, blue: 0.54)
        case "clipboard":
            Color(red: 0.56, green: 0.84, blue: 1)
        case "aiUsage":
            Color(red: 0.74, green: 0.68, blue: 1)
        case "shortcuts":
            Color(red: 1, green: 0.78, blue: 0.58)
        case "about":
            Color(red: 0.7, green: 0.82, blue: 0.96)
        default:
            Color.white.opacity(0.9)
        }
    }
}

private struct SettingsSidebarButton: View {
    let item: SettingsSidebarItem
    let isSelected: Bool
    let onClick: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.iconColor)
                    .frame(width: 15, height: 15)
                    .padding(4)
                    .background(iconBackground)

                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.075) : (isHovering ? Color.white.opacity(0.03) : .clear))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.08) : (isHovering ? Color.white.opacity(0.03) : .clear),
                        lineWidth: 0.8
                    )
            }
    }

    private var iconBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.iconColor.opacity(isSelected ? 0.16 : (isHovering ? 0.11 : 0.08)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(item.iconColor.opacity(isSelected ? 0.26 : 0.16), lineWidth: 0.8)
            }
    }
}

private struct QuitAppSidebarButton: View {
    @State private var isHovering = false

    var body: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(width: 13, height: 13)
                    .padding(3)
                    .background(iconBackground)

                Text("Quit app")
                    .font(.system(size: 11.5, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.secondary.opacity(0.88))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovering ? Color.white.opacity(0.035) : Color.white.opacity(0.02))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHovering ? Color.white.opacity(0.04) : .clear, lineWidth: 0.8)
            }
    }

    private var iconBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.red.opacity(isHovering ? 0.14 : 0.1))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.red.opacity(isHovering ? 0.24 : 0.18), lineWidth: 0.8)
            }
    }
}

private struct SettingsGeneralView: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }

    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) private var automaticallySwitchDisplay
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.extendHoverArea) private var extendHoverArea
    @Default(.hideNotchInFullscreen) private var hideNotchInFullscreen
    @Default(.hideFromScreenRecording) private var hideFromScreenRecording

    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at login")
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
            }

            Section {
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
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
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            } header: {
                SettingsSectionHeader(title: "Display settings")
            }

            Section {
                Picker("Notch height on notch displays", selection: $notchHeightMode) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                }
                .onChange(of: notchHeightMode) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }

                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                }
                .onChange(of: nonNotchHeightMode) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            } header: {
                SettingsSectionHeader(title: "Notch sizing")
            }

            Section {
                Defaults.Toggle(key: .openNotchOnHover) {
                    Text("Open notch on hover")
                }

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
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }

                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                Defaults.Toggle(key: .hideNotchInFullscreen) {
                    Text("Hide in fullscreen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
                Defaults.Toggle(key: .trackpadTabSwitch) {
                    Text("Enable gestures")
                }
            } header: {
                SettingsSectionHeader(title: "Behavior")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct SettingsMediaView: View {
    @Default(.waitInterval) private var waitInterval
    @Default(.mediaController) private var mediaController
    @Default(.enableLyrics) private var enableLyrics
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        Form {
            Section {
                Picker("Music source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
                }

                Defaults.Toggle(key: .matchAlbumArtColor) {
                    Text("Match album art color")
                }
            }

            Section {
                Toggle("Show music live activity", isOn: $coordinator.musicLiveActivityEnabled.animation())

                Stepper(value: $waitInterval, in: 0 ... 10, step: 1) {
                    HStack {
                        Text("Media timeout")
                        Spacer()
                        Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                MusicSlotConfigurationView()

                Toggle(isOn: $enableLyrics) {
                    HStack {
                        Text("Enable lyrics")
                        customBadge(text: "Beta")
                    }
                }
                .onChange(of: enableLyrics) { _, isEnabled in
                    MusicManager.shared.setLyricsEnabled(isEnabled)
                }
            } header: {
                SettingsSectionHeader(title: "Media controls")
            } footer: {
                Text("Customize which controls appear in the music player.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            MediaControllerType.allCases
        }
    }
}

private struct SettingsCommandLauncherView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Command Launcher")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Coming soon.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.76))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}
