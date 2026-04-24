import SwiftUI

private enum OnboardingStep {
    case accessibility
    case calendar
}

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .accessibility
    @State private var accessibilityAuthorized = false
    @State private var calendarAuthorizationState = CalendarManager.shared.authorizationState
    @State private var requestingAccessibility = false
    @State private var requestingCalendar = false

    private let accessibilityColor = Color(red: 0.62, green: 0.76, blue: 1)
    private let calendarColor = Color(red: 0.58, green: 0.86, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(currentColor.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(currentColor.opacity(0.22), lineWidth: 0.8)
                    }
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: step == .accessibility ? "hand.raised.fill" : "calendar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(currentColor)
                    }

                Text(step == .accessibility
                    ? "Grant the permissions Notchera needs to work properly."
                    : "One more permission before you jump in.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step == .accessibility ? "Accessibility" : "Calendar")
                    .font(.system(size: 22, weight: .semibold))

                Text(step == .accessibility
                    ? "Needed for the HUD, media controls, and system interactions."
                    : "Used to show upcoming events inside the calendar tab.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                stepDot(isActive: step == .accessibility, color: accessibilityColor)
                stepDot(isActive: step == .calendar, color: calendarColor)
            }

            if step == .accessibility {
                accessibilityActions
            } else {
                calendarActions
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(width: 360)
        .task {
            await refreshAuthorizationState()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
            CalendarManager.shared.refreshAuthorizationState()
            calendarAuthorizationState = CalendarManager.shared.authorizationState
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
                requestingAccessibility = false

                if granted {
                    withAnimation(.smooth(duration: 0.2)) {
                        step = .calendar
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshAuthorizationState()
            }
        }
    }

    private var accessibilityActions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button(requestingAccessibility ? "Allowing..." : "Allow") {
                requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(currentColor)
            .disabled(accessibilityAuthorized || requestingAccessibility)

            Spacer(minLength: 0)
        }
    }

    private var calendarActions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button(requestingCalendar ? "Allowing..." : "Allow") {
                requestCalendar()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(currentColor)
            .disabled(requestingCalendar || calendarAuthorizationState == .authorized)

            Button(calendarAuthorizationState == .authorized ? "Continue" : "Skip") {
                completeOnboarding()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(requestingCalendar)

            Spacer(minLength: 0)
        }
    }

    private func stepDot(isActive: Bool, color: Color) -> some View {
        Capsule(style: .continuous)
            .fill(isActive ? color : Color.white.opacity(0.08))
            .frame(height: 4)
    }

    private var currentColor: Color {
        step == .accessibility ? accessibilityColor : calendarColor
    }

    private func refreshAuthorizationState() async {
        accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        CalendarManager.shared.refreshAuthorizationState()
        calendarAuthorizationState = CalendarManager.shared.authorizationState
        requestingAccessibility = false
        requestingCalendar = false

        if accessibilityAuthorized, step == .accessibility {
            step = .calendar
        }
    }

    private func requestAccessibility() {
        guard !accessibilityAuthorized else { return }
        requestingAccessibility = true
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    private func requestCalendar() {
        switch calendarAuthorizationState {
        case .authorized:
            completeOnboarding()
        case .notDetermined:
            requestingCalendar = true
            Task {
                await CalendarManager.shared.requestAccess()
                await refreshAuthorizationState()
                if calendarAuthorizationState == .authorized {
                    completeOnboarding()
                }
            }
        case .denied:
            openCalendarSettings()
        case .restricted:
            completeOnboarding()
        }
    }

    private func openCalendarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preferences.users?Privacy_Calendars",
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func completeOnboarding() {
        NotcheraViewCoordinator.shared.firstLaunch = false
        onFinish()
    }
}
