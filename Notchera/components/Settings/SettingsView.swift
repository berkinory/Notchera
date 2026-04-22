import Sparkle
import SwiftUI

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
                case "Extensions":
                    GeneralSettingsView()
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
