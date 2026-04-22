import Foundation

enum AIUsageProvider: String, Codable, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        }
    }
}

enum AIUsageCredentials {
    case claude
    case codex(CodexStoredCredentials)
}

struct CodexStoredCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountId: String
}

struct AIUsageWindowSnapshot: Codable {
    var usedPercent: Double
    var remainingPercent: Double
    var resetAt: Date?
    var resetDescription: String?
}

struct AIUsageSnapshot: Codable {
    var fiveHour: AIUsageWindowSnapshot
    var weekly: AIUsageWindowSnapshot
    var fetchedAt: Date
}

struct AIUsageAccount: Identifiable, Codable {
    var id: UUID
    var alias: String
    var provider: AIUsageProvider
    var snapshot: AIUsageSnapshot?
    var lastError: String?
    var isRefreshing: Bool = false
}

extension AIUsageWindowSnapshot {
    static let empty = AIUsageWindowSnapshot(usedPercent: 0, remainingPercent: 100, resetAt: nil, resetDescription: nil)
}
