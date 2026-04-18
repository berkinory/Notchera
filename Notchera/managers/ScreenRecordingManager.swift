import Darwin
import Foundation
import SwiftUI

@MainActor
final class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()

    @Published private(set) var isMonitoring = false
    @Published private(set) var isRecording = false
    @Published private(set) var isSupported = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    private typealias ScreenWatcherPresentFn = @convention(c) () -> Bool
    private typealias RegisterNotifyProcFn = @convention(c) (
        (@convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
        Int32,
        UnsafeMutableRawPointer?
    ) -> Bool

    private let remoteConnectEvent: Int32 = 1502
    private let remoteDisconnectEvent: Int32 = 1503

    private let isScreenWatcherPresent: ScreenWatcherPresentFn?
    private let registerNotifyProc: RegisterNotifyProcFn?
    private var didRegisterNotifications = false
    private var recordingStartedAt: Date?
    private var durationTask: Task<Void, Never>?

    private init() {
        if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW) {
            defer { dlclose(handle) }

            if let watcherSymbol = dlsym(handle, "CGSIsScreenWatcherPresent") {
                isScreenWatcherPresent = unsafeBitCast(watcherSymbol, to: ScreenWatcherPresentFn.self)
            } else {
                isScreenWatcherPresent = nil
            }

            if let notifySymbol = dlsym(handle, "CGSRegisterNotifyProc") {
                registerNotifyProc = unsafeBitCast(notifySymbol, to: RegisterNotifyProcFn.self)
            } else {
                registerNotifyProc = nil
            }
        } else {
            isScreenWatcherPresent = nil
            registerNotifyProc = nil
        }

        isSupported = isScreenWatcherPresent != nil && registerNotifyProc != nil
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard isSupported else {
            isRecording = false
            recordingDuration = 0
            return
        }

        isMonitoring = true

        if !didRegisterNotifications {
            registerPrivateNotifications()
        }

        refreshStatus()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stopRecordingUI()
    }

    func refreshStatus() {
        guard isMonitoring, let isScreenWatcherPresent else { return }

        let nextValue = isScreenWatcherPresent()
        guard nextValue != isRecording else { return }

        if nextValue {
            startRecordingUI()
        } else {
            stopRecordingUI()
        }
    }

    private func startRecordingUI() {
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)) {
            isRecording = true
        }
        recordingStartedAt = Date()
        recordingDuration = 0

        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .recording,
            duration: 1.6,
            value: 1,
            label: "Started"
        )

        durationTask?.cancel()
        durationTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, isMonitoring, isRecording {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                updateDuration()
            }
        }
    }

    private func stopRecordingUI() {
        durationTask?.cancel()
        durationTask = nil
        recordingStartedAt = nil
        recordingDuration = 0

        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.9, blendDuration: 0)) {
            isRecording = false
        }

        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .recording,
            duration: 1.6,
            value: 0,
            label: "Stopped"
        )
    }

    private func updateDuration() {
        guard let recordingStartedAt else {
            recordingDuration = 0
            return
        }

        recordingDuration = Date().timeIntervalSince(recordingStartedAt)
    }

    var durationText: String {
        let totalSeconds = max(0, Int(recordingDuration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func registerPrivateNotifications() {
        guard let registerNotifyProc else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let didRegisterConnect = registerNotifyProc(screenRecordingEventCallback, remoteConnectEvent, context)
        let didRegisterDisconnect = registerNotifyProc(screenRecordingEventCallback, remoteDisconnectEvent, context)

        didRegisterNotifications = didRegisterConnect && didRegisterDisconnect
    }
}

private func screenRecordingEventCallback(
    _: Int32,
    _: Int32,
    _: Int32,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }

    let manager = Unmanaged<ScreenRecordingManager>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in
        manager.refreshStatus()
    }
}
