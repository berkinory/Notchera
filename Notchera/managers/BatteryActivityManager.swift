import Foundation
import IOKit.ps

/// Manages and monitors battery status changes on the device
/// - Note: This class uses the IOKit framework to monitor battery status
class BatteryActivityManager {
    static let shared = BatteryActivityManager()

    var onBatteryLevelChange: ((Float) -> Void)?
    var onMaxCapacityChange: ((Float) -> Void)?
    var onPowerModeChange: ((Bool) -> Void)?
    var onPowerSourceChange: ((Bool) -> Void)?
    var onChargingChange: ((Bool) -> Void)?
    var onTimeToFullChargeChange: ((Int) -> Void)?

    private var batterySource: CFRunLoopSource?
    private var observers: [(BatteryEvent) -> Void] = []
    private var previousBatteryInfo: BatteryInfo?

    enum BatteryEvent {
        case powerSourceChanged(isPluggedIn: Bool)
        case batteryLevelChanged(level: Float)
        case lowPowerModeChanged(isEnabled: Bool)
        case isChargingChanged(isCharging: Bool)
        case timeToFullChargeChanged(time: Int)
        case maxCapacityChanged(capacity: Float)
        case error(description: String)
    }

    enum BatteryError: Error {
        case powerSourceUnavailable
        case batteryInfoUnavailable(String)
        case batteryParameterMissing(String)
    }

    private let defaultBatteryInfo = BatteryInfo(
        isPluggedIn: false,
        isCharging: false,
        currentCapacity: 0,
        maxCapacity: 0,
        isInLowPowerMode: false,
        timeToFullCharge: 0
    )

    private init() {
        startMonitoring()
        setupLowPowerModeObserver()
    }


    private func setupLowPowerModeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lowPowerModeChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }


    @objc private func lowPowerModeChanged() {
        notifyBatteryChanges()
    }


    private func startMonitoring() {
        guard let powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<BatteryActivityManager>.fromOpaque(context).takeUnretainedValue()
            manager.notifyBatteryChanges()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else {
            return
        }
        batterySource = powerSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
    }


    private func stopMonitoring() {
        if let powerSource = batterySource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
            batterySource = nil
        }
    }


    private func checkAndNotify<T: Equatable>(
        previous: T,
        current: T,
        eventGenerator: (T) -> BatteryEvent
    ) {
        if previous != current {
            enqueueNotification(eventGenerator(current))
        }
    }



    private func notifyBatteryChanges() {
        let batteryInfo = getBatteryInfo()

        if let previousInfo = previousBatteryInfo {
            checkAndNotify(
                previous: previousInfo.isPluggedIn,
                current: batteryInfo.isPluggedIn,
                eventGenerator: { .powerSourceChanged(isPluggedIn: $0) }
            )

            checkAndNotify(
                previous: previousInfo.currentCapacity,
                current: batteryInfo.currentCapacity,
                eventGenerator: { .batteryLevelChanged(level: $0) }
            )

            checkAndNotify(
                previous: previousInfo.isCharging,
                current: batteryInfo.isCharging,
                eventGenerator: { .isChargingChanged(isCharging: $0) }
            )

            checkAndNotify(
                previous: previousInfo.isInLowPowerMode,
                current: batteryInfo.isInLowPowerMode,
                eventGenerator: { .lowPowerModeChanged(isEnabled: $0) }
            )

            checkAndNotify(
                previous: previousInfo.timeToFullCharge,
                current: batteryInfo.timeToFullCharge,
                eventGenerator: { .timeToFullChargeChanged(time: $0) }
            )

            checkAndNotify(
                previous: previousInfo.maxCapacity,
                current: batteryInfo.maxCapacity,
                eventGenerator: { .maxCapacityChanged(capacity: $0) }
            )
        } else {
            enqueueNotification(.powerSourceChanged(isPluggedIn: batteryInfo.isPluggedIn))
            enqueueNotification(.batteryLevelChanged(level: batteryInfo.currentCapacity))
            enqueueNotification(.isChargingChanged(isCharging: batteryInfo.isCharging))
            enqueueNotification(.lowPowerModeChanged(isEnabled: batteryInfo.isInLowPowerMode))
            enqueueNotification(.timeToFullChargeChanged(time: batteryInfo.timeToFullCharge))
            enqueueNotification(.maxCapacityChanged(capacity: batteryInfo.maxCapacity))
        }

        previousBatteryInfo = batteryInfo

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            onBatteryLevelChange?(batteryInfo.currentCapacity)
            onPowerSourceChange?(batteryInfo.isPluggedIn)
            onChargingChange?(batteryInfo.isCharging)
            onPowerModeChange?(batteryInfo.isInLowPowerMode)
            onTimeToFullChargeChange?(batteryInfo.timeToFullCharge)
            onMaxCapacityChange?(batteryInfo.maxCapacity)
        }
    }



    private func enqueueNotification(_ event: BatteryEvent) {
        notifyObservers(event: event)
    }



    func initializeBatteryInfo() -> BatteryInfo {
        previousBatteryInfo = getBatteryInfo()
        guard let batteryInfo = previousBatteryInfo else {
            return BatteryInfo(
                isPluggedIn: false,
                isCharging: false,
                currentCapacity: 0,
                maxCapacity: 0,
                isInLowPowerMode: false,
                timeToFullCharge: 0
            )
        }
        return batteryInfo
    }



    private func getBatteryInfo() -> BatteryInfo {
        do {
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
                throw BatteryError.powerSourceUnavailable
            }

            guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
                  !sources.isEmpty
            else {
                throw BatteryError.batteryInfoUnavailable("No power sources available")
            }

            let source = sources.first!

            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                throw BatteryError.batteryInfoUnavailable("Could not get power source description")
            }

            guard let currentCapacity = description[kIOPSCurrentCapacityKey] as? Float else {
                throw BatteryError.batteryParameterMissing("Current capacity")
            }

            guard let maxCapacity = description[kIOPSMaxCapacityKey] as? Float else {
                throw BatteryError.batteryParameterMissing("Max capacity")
            }

            guard let isCharging = description["Is Charging"] as? Bool else {
                throw BatteryError.batteryParameterMissing("Charging state")
            }

            guard let powerSource = description[kIOPSPowerSourceStateKey] as? String else {
                throw BatteryError.batteryParameterMissing("Power source state")
            }

            var batteryInfo = BatteryInfo(
                isPluggedIn: powerSource == kIOPSACPowerValue,
                isCharging: isCharging,
                currentCapacity: currentCapacity,
                maxCapacity: maxCapacity,
                isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                timeToFullCharge: 0
            )

            if let timeToFullCharge = description[kIOPSTimeToFullChargeKey] as? Int {
                batteryInfo.timeToFullCharge = timeToFullCharge
            }

            return batteryInfo

        } catch BatteryError.powerSourceUnavailable {
            print("⚠️ Error: Power source information unavailable")
            return defaultBatteryInfo
        } catch let BatteryError.batteryInfoUnavailable(reason) {
            print("⚠️ Error: Battery information unavailable - \(reason)")
            return defaultBatteryInfo
        } catch let BatteryError.batteryParameterMissing(parameter) {
            print("⚠️ Error: Battery parameter missing - \(parameter)")
            return defaultBatteryInfo
        } catch {
            print("⚠️ Error: Unexpected error getting battery info - \(error.localizedDescription)")
            return defaultBatteryInfo
        }
    }




    func addObserver(_ observer: @escaping (BatteryEvent) -> Void) -> Int {
        observers.append(observer)
        return observers.count - 1
    }



    func removeObserver(byId id: Int) {
        guard id >= 0, id < observers.count else { return }
        observers.remove(at: id)
    }



    private func notifyObservers(event: BatteryEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for observer in observers {
                observer(event)
            }
        }
    }

    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
}

/// Struct to hold battery information
struct BatteryInfo {
    var isPluggedIn: Bool
    var isCharging: Bool
    var currentCapacity: Float
    var maxCapacity: Float
    var isInLowPowerMode: Bool
    var timeToFullCharge: Int
}
