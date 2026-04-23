import SwiftUI

extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }

    var releaseVersionNumberPretty: String {
        "v\(releaseVersionNumber ?? "1.0.0")"
    }
}

func isNewVersion() -> Bool {
    let defaults = UserDefaults.standard
    let currentVersion = Bundle.main.releaseVersionNumber ?? "1.0"
    let savedVersion = defaults.string(forKey: "LastVersionRun") ?? ""

    if currentVersion != savedVersion {
        defaults.set(currentVersion, forKey: "LastVersionRun")
        return true
    }
    return false
}

func isExtensionRunning(_ bundleID: String) -> Bool {
    NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) != nil
}
