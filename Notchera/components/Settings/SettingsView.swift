import Sparkle
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "General"
    let updaterController: SPUStandardUpdaterController?

    private let sections: [SettingsSidebarSection] = [
        SettingsSidebarSection(
            title: "core",
            items: [
                SettingsSidebarItem(id: "General", title: "General", icon: "gear"),
                SettingsSidebarItem(id: "Appearance", title: "Appearance", icon: "eye"),
                SettingsSidebarItem(id: "Advanced", title: "Advanced", icon: "gearshape.2")
            ]
        ),
        SettingsSidebarSection(
            title: "modules",
            items: [
                SettingsSidebarItem(id: "Media", title: "Media", icon: "play.laptopcomputer"),
                SettingsSidebarItem(id: "HUD", title: "HUDs", icon: "dial.medium.fill"),
                SettingsSidebarItem(id: "Shelf", title: "Shelf", icon: "books.vertical"),
                SettingsSidebarItem(id: "Clipboard", title: "Clipboard", icon: "doc.on.clipboard"),
                SettingsSidebarItem(id: "Shortcuts", title: "Shortcuts", icon: "keyboard"),
                SettingsSidebarItem(id: "AI Usage", title: "AI Usage", icon: "brain")
            ]
        ),
        SettingsSidebarSection(
            title: "app",
            items: [
                SettingsSidebarItem(id: "About", title: "About", icon: "info.circle")
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
                    Text(section.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.68))
                        .padding(.horizontal, 8)

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
                    .font(.system(size: 17, weight: .semibold))

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
        case "General":
            GeneralSettingsView()
        case "Appearance":
            AppearanceSettingsView()
        case "Media":
            MediaSettingsView()
        case "HUD":
            HUDSettingsView()
        case "Shelf":
            ShelfSettingsView()
        case "Clipboard":
            ClipboardSettingsView()
        case "Shortcuts":
            ShortcutsSettingsView()
        case "Advanced":
            AdvancedSettingsView()
        case "AI Usage":
            AIUsageSettingsView()
        case "About":
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
            GeneralSettingsView()
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

    var id: String { title }

    var displayTitle: String {
        switch title {
        case "core":
            "Core"
        case "modules":
            "Modules"
        case "app":
            "App"
        default:
            title.capitalized
        }
    }
}

private struct SettingsSidebarItem: Identifiable {
    let id: String
    let title: String
    let icon: String

    var iconColor: Color {
        switch id {
        case "General":
            Color(red: 0.62, green: 0.76, blue: 1)
        case "Appearance":
            Color(red: 1, green: 0.72, blue: 0.88)
        case "Advanced":
            Color(red: 1, green: 0.72, blue: 0.56)
        case "Media":
            Color(red: 0.58, green: 0.86, blue: 0.72)
        case "HUD":
            Color(red: 1, green: 0.66, blue: 0.5)
        case "Shelf":
            Color(red: 0.84, green: 0.76, blue: 1)
        case "Clipboard":
            Color(red: 0.56, green: 0.84, blue: 1)
        case "Shortcuts":
            Color(red: 0.98, green: 0.82, blue: 0.54)
        case "AI Usage":
            Color(red: 0.74, green: 0.68, blue: 1)
        case "About":
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
