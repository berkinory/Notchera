import CoreMediaIO
import Foundation
import SwiftUI

private func cameraActivityPropertyListener(
    objectID _: CMIOObjectID,
    numberAddresses _: UInt32,
    addresses _: UnsafePointer<CMIOObjectPropertyAddress>?,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return OSStatus(kCMIOHardwareNoError) }

    let manager = Unmanaged<CameraActivityManager>.fromOpaque(clientData).takeUnretainedValue()
    Task { @MainActor in
        manager.refreshStatus()
    }

    return OSStatus(kCMIOHardwareNoError)
}

@MainActor
final class CameraActivityManager: ObservableObject {
    static let shared = CameraActivityManager()

    @Published private(set) var isMonitoring = false
    @Published private(set) var isActive = false

    private var cameraDeviceIDs: [CMIOObjectID] = []
    private var isListenerRegistered = false

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        cameraDeviceIDs = enumerateCameraDevices()
        isMonitoring = true

        if !cameraDeviceIDs.isEmpty {
            addListeners()
            refreshStatus()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        removeListeners()
        cameraDeviceIDs.removeAll()
        isMonitoring = false
        isActive = false
    }

    func refreshStatus() {
        guard isMonitoring else { return }

        let nextValue = cameraDeviceIDs.contains(where: isDeviceRunning)
        guard nextValue != isActive else { return }

        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)) {
            isActive = nextValue
        }
    }

    private func enumerateCameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == OSStatus(kCMIOHardwareNoError), dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var deviceIDs = [CMIOObjectID](repeating: 0, count: count)

        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &dataSize,
            &deviceIDs
        ) == OSStatus(kCMIOHardwareNoError) else {
            return []
        }

        return deviceIDs.filter(isVideoInputDevice)
    }

    private func isVideoInputDevice(_ deviceID: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        return CMIOObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == OSStatus(kCMIOHardwareNoError)
            && dataSize > 0
    }

    private func addListeners() {
        guard !cameraDeviceIDs.isEmpty, !isListenerRegistered else { return }

        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        var registeredAny = false

        for deviceID in cameraDeviceIDs {
            let status = CMIOObjectAddPropertyListener(deviceID, &address, cameraActivityPropertyListener, context)
            if status == OSStatus(kCMIOHardwareNoError) {
                registeredAny = true
            }
        }

        isListenerRegistered = registeredAny
    }

    private func removeListeners() {
        guard isListenerRegistered else { return }

        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()

        for deviceID in cameraDeviceIDs {
            CMIOObjectRemovePropertyListener(deviceID, &address, cameraActivityPropertyListener, context)
        }

        isListenerRegistered = false
    }

    private func isDeviceRunning(_ deviceID: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        return CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &dataSize, &isRunning) == OSStatus(kCMIOHardwareNoError)
            && isRunning != 0
    }
}
