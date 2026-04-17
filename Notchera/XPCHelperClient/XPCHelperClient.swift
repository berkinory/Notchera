import ApplicationServices
import AsyncXPCConnection
import Cocoa
import Foundation

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()

    private let serviceName = "com.notchera.app.NotcheraXPCHelper"

    private var remoteService: RemoteXPCService<NotcheraXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?

    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }



    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<NotcheraXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }

        let conn = NSXPCConnection(serviceName: serviceName)

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }

        conn.resume()

        let service = RemoteXPCService<NotcheraXPCHelperProtocol>(
            connection: conn,
            remoteInterface: NotcheraXPCHelperProtocol.self
        )

        connection = conn
        remoteService = service
        return service
    }

    @MainActor
    private func getRemoteService() -> RemoteXPCService<NotcheraXPCHelperProtocol>? {
        remoteService
    }

    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }



    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                _ = await isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }


    var isMonitoring: Bool {
        monitoringTask != nil
    }



    private nonisolated func currentProcessAccessibilityAuthorized(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        return AXIsProcessTrusted()
    }

    nonisolated func requestAccessibilityAuthorization() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)

            let granted = currentProcessAccessibilityAuthorized(promptIfNeeded: true)
            notifyAuthorizationChange(granted)

            if !granted,
               let settingsURL = URL(
                   string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
               )
            {
                NSWorkspace.shared.open(settingsURL)
            }
        }
    }

    nonisolated func isAccessibilityAuthorized() async -> Bool {
        let result = currentProcessAccessibilityAuthorized()
        await MainActor.run {
            notifyAuthorizationChange(result)
        }
        return result
    }

    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        if currentProcessAccessibilityAuthorized() {
            await MainActor.run {
                notifyAuthorizationChange(true)
            }
            return true
        }

        guard promptIfNeeded else {
            await MainActor.run {
                notifyAuthorizationChange(false)
            }
            return false
        }

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        _ = currentProcessAccessibilityAuthorized(promptIfNeeded: true)

        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(250))

            let granted = currentProcessAccessibilityAuthorized()
            if granted {
                await MainActor.run {
                    notifyAuthorizationChange(true)
                }
                return true
            }
        }

        await MainActor.run {
            notifyAuthorizationChange(false)

            if let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) {
                NSWorkspace.shared.open(settingsURL)
            }
        }
        return false
    }



    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }

    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }



    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }

    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
