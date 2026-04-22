import Defaults
import SwiftUI

struct AIUsageSettingsView: View {
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
                                NotcheraSpinner(color: .white.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: 12, height: 12)
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
    @State private var selectedAccountID: AIUsageAccount.ID?

    private var accountIDs: [AIUsageAccount.ID] {
        store.accounts.map(\.id)
    }

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                VStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))

                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.78))
                    }
                    .frame(width: 34, height: 34)

                    VStack(spacing: 3) {
                        Text("No accounts yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Add Codex or Claude accounts in Settings.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.secondary.opacity(0.76))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 6)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(store.accounts) { account in
                            AIUsageAccountRow(
                                account: account,
                                showRemaining: aiUsageShowRemaining,
                                isSelected: selectedAccountID == account.id,
                                action: {
                                    selectedAccountID = selectedAccountID == account.id ? nil : account.id
                                }
                            )
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
            syncSelection()
        }
        .onChange(of: accountIDs) { _, _ in
            syncSelection()
        }
    }

    private func syncSelection() {
        guard !store.accounts.isEmpty else {
            selectedAccountID = nil
            return
        }

        if let selectedAccountID,
           !store.accounts.contains(where: { $0.id == selectedAccountID })
        {
            self.selectedAccountID = nil
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

private struct AIUsageAccountRow: View {
    let account: AIUsageAccount
    let showRemaining: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: isSelected ? 7 : 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    AIUsageProviderIcon(provider: account.provider, size: 12)

                    Text(account.alias)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.74))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if account.isRefreshing {
                        NotcheraSpinner(color: Color.white.opacity(0.82), lineWidth: 1.4)
                            .frame(width: 8, height: 8)
                    }

                    if let snapshot = account.snapshot {
                        HStack(spacing: 8) {
                            AIUsageCompactMetric(label: "5H", snapshot: snapshot.fiveHour, showRemaining: showRemaining)
                            AIUsageCompactMetric(label: "W", snapshot: snapshot.weekly, showRemaining: showRemaining)
                        }
                    } else {
                        Text(statusText)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.72))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.horizontal, 8)
                .background(backgroundShape.fill(backgroundFill))
                .overlay {
                    backgroundShape
                        .strokeBorder(borderColor, lineWidth: 0.7)
                }
                .contentShape(backgroundShape)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }

            if isSelected {
                selectedDetail
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var selectedDetail: some View {
        Group {
            if let snapshot = account.snapshot {
                let percentageWidth = AIUsageMetricTone.percentageWidth(
                    for: [snapshot.fiveHour, snapshot.weekly],
                    showRemaining: showRemaining
                )

                VStack(alignment: .leading, spacing: 6) {
                    AIUsageExpandedMetric(title: "Current", snapshot: snapshot.fiveHour, showRemaining: showRemaining, isWeekly: false, percentageWidth: percentageWidth)
                    AIUsageExpandedMetric(title: "Weekly", snapshot: snapshot.weekly, showRemaining: showRemaining, isWeekly: true, percentageWidth: percentageWidth)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.045), lineWidth: 0.6)
                }
            } else if let lastError = account.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            } else {
                Text("No usage yet")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.82))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            }
        }
    }

    private var statusText: String {
        if let lastError = account.lastError, !lastError.isEmpty {
            return "Error"
        }

        return "Empty"
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Color.white.opacity(0.07)
        }

        if isHovered {
            return Color.white.opacity(0.055)
        }

        return Color.white.opacity(0.04)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.white.opacity(0.09)
        }

        if isHovered {
            return Color.white.opacity(0.065)
        }

        return Color.white.opacity(0.05)
    }
}

private struct AIUsageCompactMetric: View {
    let label: String
    let snapshot: AIUsageWindowSnapshot
    let showRemaining: Bool

    private var displayPercent: Double {
        showRemaining ? snapshot.remainingPercent : snapshot.usedPercent
    }

    private var metricColor: Color {
        AIUsageMetricTone.color(for: snapshot.usedPercent)
    }

    private let metricWidth: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .frame(minWidth: 14, alignment: .leading)

                Spacer(minLength: 4)

                Text(displayPercent.formattedPercent)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(metricColor)
                    .fixedSize()
            }
            .frame(width: metricWidth)

            AIUsageProgressBar(value: displayPercent, color: metricColor)
                .frame(width: metricWidth, height: 4)
        }
    }
}

private struct AIUsageExpandedMetric: View {
    let title: String
    let snapshot: AIUsageWindowSnapshot
    let showRemaining: Bool
    let isWeekly: Bool
    let percentageWidth: CGFloat

    private var displayPercent: Double {
        showRemaining ? snapshot.remainingPercent : snapshot.usedPercent
    }

    private var metricColor: Color {
        AIUsageMetricTone.color(for: snapshot.usedPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(AIUsageMetricTone.resetText(for: snapshot, isWeekly: isWeekly))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(alignment: .center, spacing: 7) {
                AIUsageProgressBar(value: displayPercent, color: metricColor)
                    .frame(height: 5)

                Text(displayPercent.formattedPercent)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(metricColor)
                    .monospacedDigit()
                    .frame(width: percentageWidth, alignment: .trailing)
            }
        }
    }
}

private enum AIUsageMetricTone {
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

    static func color(for usedPercent: Double) -> Color {
        if usedPercent < 60 {
            return .green
        }
        if usedPercent < 85 {
            return .yellow
        }
        return .red
    }

    static func percentageWidth(for snapshots: [AIUsageWindowSnapshot], showRemaining: Bool) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

        return (snapshots.map { snapshot in
            let value = showRemaining ? snapshot.remainingPercent : snapshot.usedPercent
            return (value.formattedPercent as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0).rounded(.up)
    }
}

private struct AIUsageProgressBar: View {
    let value: Double
    let color: Color

    private var clampedValue: CGFloat {
        CGFloat(min(max(value, 0), 100) / 100)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fillWidth = max(width * clampedValue, clampedValue == 0 ? 0 : 6)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(color.opacity(0.92))
                    .frame(width: fillWidth)
            }
        }
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
            if loginSession.isBusy, provider == .codex {
                NotcheraSpinner(color: .white.opacity(0.9), lineWidth: 1.6)
                    .frame(width: 14, height: 14)
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

private extension Double {
    var formattedPercent: String {
        String(format: "%.0f%%", self)
    }
}
