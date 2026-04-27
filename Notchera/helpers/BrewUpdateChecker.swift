import Foundation

struct BrewUpdateCheckResult: Equatable {
    let installedVersion: String?
    let latestVersion: String
    let updateAvailable: Bool
}

enum BrewUpdateChecker {
    static func check() async throws -> BrewUpdateCheckResult {
        let data = try await runBrewInfo()
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)

        guard let cask = response.casks.first else {
            throw NSError(
                domain: "BrewUpdateChecker",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Notchera is not installed via Homebrew."]
            )
        }

        return BrewUpdateCheckResult(
            installedVersion: cask.installed,
            latestVersion: cask.version,
            updateAvailable: cask.outdated
        )
    }

    private static func runBrewInfo() async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            guard let brewPath = brewExecutablePath() else {
                throw NSError(
                    domain: "BrewUpdateChecker",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Homebrew is not available on this Mac."]
                )
            }

            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["info", "--cask", "--json=v2", "notchera"]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw NSError(
                    domain: "BrewUpdateChecker",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Homebrew is not available on this Mac."]
                )
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "BrewUpdateChecker",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Failed to query Homebrew."]
                )
            }

            return outputData
        }.value
    }

    private static func brewExecutablePath() -> String? {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"].map { "\($0)/bin/brew" },
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ].compactMap { $0 }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }
}

private struct BrewInfoResponse: Decodable {
    let casks: [BrewCaskInfo]
}

private struct BrewCaskInfo: Decodable {
    let version: String
    let installed: String?
    let outdated: Bool
}
