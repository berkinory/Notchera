import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {
    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()



    private init() {
        setupPowerStatus()
        setupMonitor()
    }


    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }


    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self else { return }
            handleBatteryEvent(event)
        }
    }



    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case let .powerSourceChanged(isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? "Plugged In" : "Unplugged"
                self.notifyImportanChangeStatus()
            }

        case let .batteryLevelChanged(level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation {
                self.levelBattery = level
            }

        case let .lowPowerModeChanged(isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            notifyImportanChangeStatus()
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }

        case let .isChargingChanged(isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(maxCapacity)")
            print("levelBattery: \(levelBattery)")
            notifyImportanChangeStatus()
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                        ? "Charging battery"
                        : (self.levelBattery < self.maxCapacity ? "Not charging" : "Full charge")
            }

        case let .timeToFullChargeChanged(time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case let .maxCapacityChanged(capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case let .error(description):
            print("⚠️ Error: \(description)")
        }
    }



    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? "Plugged In" : "Unplugged"
        }
    }



    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }
}
