import CoreAudio
import Foundation
import SwiftUI

private func microphoneActivityPropertyListener(
    inObjectID _: AudioObjectID,
    inNumberAddresses _: UInt32,
    inAddresses _: UnsafePointer<AudioObjectPropertyAddress>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }

    let manager = Unmanaged<MicrophoneActivityManager>.fromOpaque(inClientData).takeUnretainedValue()
    Task { @MainActor in
        manager.refreshStatus()
    }

    return noErr
}

@MainActor
final class MicrophoneActivityManager: ObservableObject {
    static let shared = MicrophoneActivityManager()

    @Published private(set) var isMonitoring = false
    @Published private(set) var isActive = false

    private var defaultInputDevice: AudioDeviceID = 0
    private var isListenerRegistered = false

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        defaultInputDevice = getDefaultInputDevice()
        isMonitoring = true

        guard defaultInputDevice != 0 else {
            isActive = false
            return
        }

        addListener()
        refreshStatus()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        removeListener()
        defaultInputDevice = 0
        isMonitoring = false
        isActive = false
    }

    func refreshStatus() {
        guard isMonitoring, defaultInputDevice != 0 else { return }

        let nextValue = isDeviceRunning(defaultInputDevice)
        guard nextValue != isActive else { return }

        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)) {
            isActive = nextValue
        }
    }

    private func getDefaultInputDevice() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        ) == noErr else {
            return 0
        }

        return deviceID
    }

    private func addListener() {
        guard defaultInputDevice != 0, !isListenerRegistered else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            defaultInputDevice,
            &address,
            microphoneActivityPropertyListener,
            context
        )

        isListenerRegistered = status == noErr
    }

    private func removeListener() {
        guard defaultInputDevice != 0, isListenerRegistered else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(defaultInputDevice, &address, microphoneActivityPropertyListener, context)
        isListenerRegistered = false
    }

    private func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isRunning) == noErr
            && isRunning != 0
    }
}
