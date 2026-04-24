import Defaults
import SwiftUI

struct ClipboardSettingsView: View {
    @Default(.enableClipboardHistory) var enableClipboardHistory
    @Default(.hideClipboardFromTabs) var hideClipboardFromTabs
    @Default(.clipboardSelectionAction) var clipboardSelectionAction
    @Default(.clipboardHistoryRetention) var clipboardHistoryRetention
    @Default(.clipboardHistoryMaxStoredItems) var clipboardHistoryMaxStoredItems
    @State private var accessibilityAuthorized = false

    private var retentionSliderValue: Binding<Double> {
        Binding(
            get: { Double(ClipboardHistoryRetention.allCases.firstIndex(of: clipboardHistoryRetention) ?? 0) },
            set: { newValue in
                let index = min(max(Int(newValue.rounded()), 0), ClipboardHistoryRetention.allCases.count - 1)
                clipboardHistoryRetention = ClipboardHistoryRetention.allCases[index]
                ClipboardHistoryManager.shared.pruneExpiredItems()
            }
        )
    }

    private var maxStoredItemsValue: Binding<Double> {
        Binding(
            get: { Double(clipboardHistoryMaxStoredItems) },
            set: { newValue in
                clipboardHistoryMaxStoredItems = Int(newValue.rounded())
                ClipboardHistoryManager.shared.pruneExpiredItems()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardHistory) {
                    Text("Enable clipboard history")
                }

                if enableClipboardHistory {
                    Defaults.Toggle(key: .hideClipboardFromTabs) {
                        Text("Hide from tabs")
                    }
                }
            }

            if enableClipboardHistory {
                Section {
                    HStack(spacing: 8) {
                        ClipboardSelectionOptionCard(
                            title: "Copy",
                            systemImage: "document.on.document.fill",
                            isSelected: clipboardSelectionAction == .copy,
                            action: {
                                clipboardSelectionAction = .copy
                            }
                        )

                        ClipboardSelectionOptionCard(
                            title: "Paste",
                            systemImage: "list.clipboard.fill",
                            isSelected: clipboardSelectionAction == .paste,
                            action: {
                                clipboardSelectionAction = .paste
                            }
                        )
                    }
                    .padding(.vertical, 4)

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
                } header: {
                    SettingsSectionHeader(title: "On item select")
                }

                Section {
                    SettingsSliderRow(
                        title: "Keep clipboard history",
                        value: retentionSliderValue,
                        range: 0 ... Double(ClipboardHistoryRetention.allCases.count - 1),
                        step: 1,
                        formatValue: { value in
                            let index = min(max(Int(value.rounded()), 0), ClipboardHistoryRetention.allCases.count - 1)
                            return ClipboardHistoryRetention.allCases[index].rawValue
                        }
                    )

                    SettingsSliderRow(
                        title: "Max stored items",
                        value: maxStoredItemsValue,
                        range: 1 ... 100,
                        step: 1,
                        showsTicks: false,
                        formatValue: { value in
                            String(Int(value.rounded()))
                        }
                    )
                }

                Button(role: .destructive) {
                    ClipboardHistoryManager.shared.clear()
                } label: {
                    Label("Clear clipboard history", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
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

private struct ClipboardSelectionOptionCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        SettingsIconOptionCard(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected,
            action: action
        )
    }
}
