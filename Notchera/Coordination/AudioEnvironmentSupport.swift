import AppKit
import Carbon
import CoreAudio
import Defaults
import IOBluetooth

private struct BluetoothAudioPresentation {
    let title: String
    let symbol: String
}

private enum BluetoothAudioKind {
    case speaker
    case headphones
    case generic

    var symbolName: String {
        switch self {
        case .speaker:
            "hifispeaker.fill"
        case .headphones:
            "headphones"
        case .generic:
            "airpods"
        }
    }
}

@MainActor
final class BluetoothAudioMonitor: NSObject {
    static let shared = BluetoothAudioMonitor()

    private let bluetoothPreferencesSuite = "/Library/Preferences/com.apple.Bluetooth"
    private let appleVendorID: UInt16 = 0x05AC
    private let airPodsSymbolByProductID: [UInt16: String] = [
        0x200F: "airpods",
        0x2013: "airpods.gen3",
        0x2019: "airpods.gen4",
        0x201B: "airpods.gen4",
        0x200A: "airpods.max",
        0x201F: "airpods.max",
        0x200E: "airpods.pro",
        0x2014: "airpods.pro",
        0x2024: "airpods.pro",
        0x2027: "airpods.pro",
    ]

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var knownDeviceKeys: Set<String> = []
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.5
    private var lastPresentedAt: [String: Date] = [:]
    private let presentationCooldown: TimeInterval = 2
    private var startupSuppressedDeviceKey: String?
    private var startupSuppressionDeadline: Date = .distantPast

    override private init() {
        super.init()
    }

    func start() {
        guard connectNotification == nil else { return }

        let initialDevices = connectedAudioDevices()
        knownDeviceKeys = Set(initialDevices.map(deviceKey(for:)))
        startupSuppressedDeviceKey = currentBluetoothOutputDeviceKey(in: initialDevices)
        startupSuppressionDeadline = Date().addingTimeInterval(5)

        refreshDisconnectNotifications(for: initialDevices)
        startPolling()
        startAudioRouteMonitoring()

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(_:device:))
        )
    }

    @objc
    private func bluetoothDeviceConnected(
        _: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard isAudioDevice(device) else { return }

        registerDisconnectNotification(for: device)
        syncConnectedDevices(showHUDForNewDevices: false)
        present(device)
    }

    @objc
    private func bluetoothDeviceDisconnected(
        _: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        unregisterDisconnectNotification(for: device)
        syncConnectedDevices(showHUDForNewDevices: false)
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncConnectedDevices(showHUDForNewDevices: true)
            }
        }
    }

    private func startAudioRouteMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.handleAudioRouteChange()
            }
        }
    }

    private func handleAudioRouteChange() {
        let devices = connectedAudioDevices()

        if let outputDeviceKey = currentBluetoothOutputDeviceKey(in: devices) {
            if shouldSuppressStartupPresentation(for: outputDeviceKey) {
                return
            }

            if let matchingDevice = devices.first(where: { deviceKey(for: $0) == outputDeviceKey }) {
                present(matchingDevice)
            }
            return
        }

        if Date() >= startupSuppressionDeadline {
            startupSuppressedDeviceKey = nil
        }
    }

    private func syncConnectedDevices(showHUDForNewDevices: Bool) {
        let devices = connectedAudioDevices()
        let nextKeys = Set(devices.map(deviceKey(for:)))
        let newDevices = devices.filter { !knownDeviceKeys.contains(deviceKey(for: $0)) }
        let staleKeys = knownDeviceKeys.subtracting(nextKeys)

        knownDeviceKeys = nextKeys
        for staleKey in staleKeys {
            lastPresentedAt.removeValue(forKey: staleKey)
        }

        refreshDisconnectNotifications(for: devices)

        guard showHUDForNewDevices else { return }

        for device in newDevices {
            present(device)
        }
    }

    private func present(_ device: IOBluetoothDevice) {
        guard Defaults[.hudReplacement], Defaults[.showBluetoothAudioIndicator] else { return }

        let key = deviceKey(for: device)
        if shouldSuppressStartupPresentation(for: key) {
            return
        }

        let now = Date()
        if let lastPresentedAt = lastPresentedAt[key],
           now.timeIntervalSince(lastPresentedAt) < presentationCooldown
        {
            return
        }

        lastPresentedAt[key] = now

        let presentation = presentation(for: device)
        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .bluetoothAudio,
            duration: 2.5,
            value: 1,
            icon: presentation.symbol,
            label: presentation.title
        )
    }

    private func connectedAudioDevices() -> [IOBluetoothDevice] {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return pairedDevices.filter { $0.isConnected() && isAudioDevice($0) }
    }

    private func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        let audioSink = IOBluetoothSDPUUID(uuid16: 0x110B)
        let headset = IOBluetoothSDPUUID(uuid16: 0x1108)
        let handsfree = IOBluetoothSDPUUID(uuid16: 0x111E)

        if device.getServiceRecord(for: audioSink) != nil {
            return true
        }

        if device.getServiceRecord(for: headset) != nil {
            return true
        }

        if device.getServiceRecord(for: handsfree) != nil {
            return true
        }

        let majorClass = (device.classOfDevice >> 8) & 0x1F
        return majorClass == 0x04
    }

    private func presentation(for device: IOBluetoothDevice) -> BluetoothAudioPresentation {
        let title = normalizedDeviceName(device.name) ?? "Bluetooth Audio"
        let fallbackSymbol = genericSymbol(for: device, name: title)
        let preferredSymbol = airPodsSymbol(for: device, name: title) ?? fallbackSymbol
        let symbol = resolvedSymbolName(preferredSymbol, fallback: fallbackSymbol)
        return BluetoothAudioPresentation(title: title, symbol: symbol)
    }

    private func refreshDisconnectNotifications(for devices: [IOBluetoothDevice]) {
        let activeKeys = Set(devices.map(deviceKey(for:)))

        for device in devices {
            registerDisconnectNotification(for: device)
        }

        let staleKeys = disconnectNotifications.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            disconnectNotifications[key]?.unregister()
            disconnectNotifications.removeValue(forKey: key)
        }
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice) {
        let key = deviceKey(for: device)
        guard disconnectNotifications[key] == nil else { return }

        disconnectNotifications[key] = device.register(
            forDisconnectNotification: self,
            selector: #selector(bluetoothDeviceDisconnected(_:device:))
        )
    }

    private func unregisterDisconnectNotification(for device: IOBluetoothDevice) {
        let key = deviceKey(for: device)
        disconnectNotifications[key]?.unregister()
        disconnectNotifications.removeValue(forKey: key)
    }

    private func currentBluetoothOutputDeviceKey(in devices: [IOBluetoothDevice]) -> String? {
        let outputDeviceID = currentOutputDeviceID()
        guard outputDeviceID != kAudioObjectUnknown,
              isBluetoothOutputDevice(outputDeviceID),
              let outputDeviceName = outputDeviceName(outputDeviceID)
        else {
            return nil
        }

        if let matchingDevice = devices.first(where: {
            normalizedName($0.name) == normalizedName(outputDeviceName)
        }) {
            return deviceKey(for: matchingDevice)
        }

        if devices.count == 1, let onlyDevice = devices.first {
            return deviceKey(for: onlyDevice)
        }

        return nil
    }

    private func shouldSuppressStartupPresentation(for deviceKey: String) -> Bool {
        if Date() >= startupSuppressionDeadline {
            startupSuppressedDeviceKey = nil
            return false
        }

        guard startupSuppressedDeviceKey == deviceKey else { return false }
        return true
    }

    private func currentOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private func isBluetoothOutputDevice(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &transportType
        )

        guard status == noErr else { return false }

        return transportType == kAudioDeviceTransportTypeBluetooth ||
            transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    private func outputDeviceName(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else { return nil }
        let result = name as String
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
    }

    private func normalizedName(_ value: String?) -> String {
        guard let value else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func genericSymbol(for device: IOBluetoothDevice, name: String) -> String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("speaker") || normalizedName.contains("boombox") {
            return BluetoothAudioKind.speaker.symbolName
        }

        if normalizedName.contains("headset") ||
            normalizedName.contains("hands-free") ||
            normalizedName.contains("headphone") ||
            normalizedName.contains("earbuds") ||
            normalizedName.contains("buds")
        {
            return BluetoothAudioKind.headphones.symbolName
        }

        let minorClass = (device.classOfDevice >> 2) & 0x3F
        switch minorClass {
        case 0x01, 0x02, 0x06:
            return BluetoothAudioKind.headphones.symbolName
        case 0x08, 0x0C:
            return BluetoothAudioKind.speaker.symbolName
        default:
            return BluetoothAudioKind.generic.symbolName
        }
    }

    private func airPodsSymbol(for device: IOBluetoothDevice, name: String) -> String? {
        if let productID = airPodsProductID(for: device),
           let symbol = airPodsSymbolByProductID[productID]
        {
            return symbol
        }

        let normalizedName = name.lowercased()
        guard normalizedName.contains("airpods") else { return nil }

        if normalizedName.contains("max") {
            return "airpods.max"
        }

        if normalizedName.contains("pro") {
            return "airpods.pro"
        }

        if normalizedName.contains("gen 4") ||
            normalizedName.contains("gen4") ||
            normalizedName.contains("4th") ||
            normalizedName.contains("airpods 4") ||
            normalizedName.contains("airpods4")
        {
            return "airpods.gen4"
        }

        if normalizedName.contains("gen 3") ||
            normalizedName.contains("gen3") ||
            normalizedName.contains("3rd") ||
            normalizedName.contains("third") ||
            normalizedName.contains("airpods 3") ||
            normalizedName.contains("airpods3")
        {
            return "airpods.gen3"
        }

        return "airpods"
    }

    private func airPodsProductID(for device: IOBluetoothDevice) -> UInt16? {
        guard let payload = bluetoothCachePayload(for: device) else { return nil }

        let vendorKeys = [
            "VendorID",
            "vendor_id",
            "vendorID",
            "device_vendorID",
            "DeviceVendorID",
            "VendorId",
            "Vendor ID",
        ]
        let productKeys = [
            "ProductID",
            "product_id",
            "productID",
            "device_productID",
            "DeviceProductID",
            "ProductId",
            "Product ID",
        ]

        let vendorID = extractUInt16(from: payload, keys: vendorKeys)
        let productID = extractUInt16(from: payload, keys: productKeys)

        guard let productID, airPodsSymbolByProductID[productID] != nil else { return nil }
        guard vendorID == nil || vendorID == appleVendorID else { return nil }
        return productID
    }

    private func bluetoothCachePayload(for device: IOBluetoothDevice) -> [String: Any]? {
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite),
              let deviceCache = preferences.object(forKey: "DeviceCache") as? [String: Any]
        else {
            return nil
        }

        let targetAddress = normalizedBluetoothAddress(device.addressString)
        guard !targetAddress.isEmpty else { return nil }

        for (key, value) in deviceCache {
            guard let payload = value as? [String: Any] else { continue }

            if normalizedBluetoothAddress(key) == targetAddress {
                return payload
            }

            if let payloadAddress = normalizedBluetoothAddress(from: payload["DeviceAddress"])
                ?? normalizedBluetoothAddress(from: payload["Address"])
                ?? normalizedBluetoothAddress(from: payload["BD_ADDR"])
                ?? normalizedBluetoothAddress(from: payload["device_address"]),
                payloadAddress == targetAddress
            {
                return payload
            }
        }

        return nil
    }

    private func extractUInt16(from payload: [String: Any], keys: [String]) -> UInt16? {
        for key in keys {
            guard let rawValue = payload[key] else { continue }

            if let number = rawValue as? NSNumber {
                return UInt16(truncatingIfNeeded: number.uint16Value)
            }

            if let intValue = rawValue as? Int {
                return UInt16(truncatingIfNeeded: intValue)
            }

            if let stringValue = rawValue as? String {
                let normalizedValue = stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if normalizedValue.hasPrefix("0x"),
                   let parsedValue = UInt16(normalizedValue.dropFirst(2), radix: 16)
                {
                    return parsedValue
                }

                if let parsedValue = UInt16(normalizedValue, radix: 10) {
                    return parsedValue
                }
            }
        }

        return nil
    }

    private func resolvedSymbolName(_ symbol: String, fallback: String) -> String {
        if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            return symbol
        }

        return NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil
            ? fallback
            : BluetoothAudioKind.generic.symbolName
    }

    private func deviceKey(for device: IOBluetoothDevice) -> String {
        let address = normalizedBluetoothAddress(device.addressString)
        if !address.isEmpty {
            return address
        }

        let name = normalizedDeviceName(device.name) ?? "unknown"
        return name.lowercased()
    }

    private func normalizedDeviceName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func normalizedBluetoothAddress(from value: Any?) -> String? {
        if let stringValue = value as? String {
            let normalizedValue = normalizedBluetoothAddress(stringValue)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }

        return nil
    }

    private func normalizedBluetoothAddress(_ value: String?) -> String {
        guard let value else { return "" }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }
}

final class InputSourceMonitor {
    static let shared = InputSourceMonitor()

    private var observer: NSObjectProtocol?
    private var currentLabel = ""

    private init() {}

    func start() {
        guard observer == nil else { return }

        currentLabel = Self.currentInputSourceLabel()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleInputSourceChange()
            }
        }
    }

    @MainActor
    private func handleInputSourceChange() {
        let nextLabel = Self.currentInputSourceLabel()
        guard !nextLabel.isEmpty, nextLabel != currentLabel else { return }

        currentLabel = nextLabel
        guard Defaults[.showInputSourceIndicator] else { return }

        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .inputSource,
            duration: 1.0,
            value: 1,
            icon: "translate",
            label: nextLabel
        )
    }

    private static func currentInputSourceLabel() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

        if let languagesPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(languagesPointer).takeUnretainedValue() as NSArray
            if let language = languages.firstObject as? String {
                let normalized = normalizeLanguageCode(language)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        if let sourceIDPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPointer).takeUnretainedValue() as String
            let normalized = normalizeSourceID(sourceID)
            if !normalized.isEmpty {
                return normalized
            }
        }

        if let localizedNamePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            let localizedName = Unmanaged<CFString>.fromOpaque(localizedNamePointer).takeUnretainedValue() as String
            let trimmedName = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                return trimmedName.prefix(4).uppercased()
            }
        }

        return ""
    }

    private static func normalizeLanguageCode(_ language: String) -> String {
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLanguage.isEmpty else { return "" }

        let locale = Locale(identifier: trimmedLanguage)
        let baseCode = locale.language.languageCode?.identifier ?? trimmedLanguage
        return String(baseCode.prefix(4)).uppercased()
    }

    private static func normalizeSourceID(_ sourceID: String) -> String {
        let candidate = sourceID
            .split(separator: ".")
            .reversed()
            .first(where: { $0.rangeOfCharacter(from: .letters) != nil })?
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .uppercased() ?? ""

        return String(candidate.prefix(4))
    }
}
