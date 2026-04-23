import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct ClipboardSettingsView: View {
    @Default(.enableClipboardHistory) var enableClipboardHistory
    @Default(.clipboardSelectionAction) var clipboardSelectionAction
    @Default(.clipboardHistoryRetention) var clipboardHistoryRetention
    @Default(.clipboardHistoryMaxStoredItems) var clipboardHistoryMaxStoredItems
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardHistory) {
                    Text("Enable clipboard history")
                }
            }

            Section {
                Picker("On item select", selection: $clipboardSelectionAction) {
                    ForEach(ClipboardSelectionAction.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }

                if clipboardSelectionAction == .paste, !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste on select sends Command-V to the focused app. Accessibility access is required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Request Accessibility") {
                            XPCHelperClient.shared.requestAccessibilityAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                }
            }
            .disabled(!enableClipboardHistory)

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
