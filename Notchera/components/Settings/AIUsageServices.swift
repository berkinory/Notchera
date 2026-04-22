import CryptoKit
import Network
import Security
import SwiftUI

final class AIUsageStore: ObservableObject {
    static let shared = AIUsageStore()

    @Published private(set) var accounts: [AIUsageAccount] = []

    private let credentialStore = AIUsageCredentialStore.shared
    private let service = AIUsageService()
    private let fileURL: URL
    private let cacheTTL: TimeInterval = 3 * 60

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Notchera", isDirectory: true)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = baseDirectory.appendingPathComponent("ai-usage-accounts.json")
        load()
    }

    func addAccount(alias: String, provider: AIUsageProvider, credentials: AIUsageCredentials) async {
        let account = AIUsageAccount(
            id: UUID(),
            alias: alias,
            provider: provider,
            snapshot: nil,
            lastError: nil
        )

        do {
            try credentialStore.store(credentials, for: account)
            accounts.append(account)
            save()
            await refreshAccount(id: account.id, force: true)
        } catch {
            print("[AIUsageStore] Failed to store credentials: \(error)")
        }
    }

    func removeAccount(id: UUID) {
        if let account = accounts.first(where: { $0.id == id }) {
            try? credentialStore.removeCredentials(for: account)
        }
        accounts.removeAll { $0.id == id }
        save()
    }

    func refreshIfNeeded(force: Bool) async {
        for account in accounts {
            guard force || shouldRefresh(account) else {
                continue
            }
            await refreshAccount(id: account.id, force: force)
        }
    }

    private func shouldRefresh(_ account: AIUsageAccount) -> Bool {
        guard let fetchedAt = account.snapshot?.fetchedAt else {
            return true
        }

        return Date().timeIntervalSince(fetchedAt) >= cacheTTL
    }

    private func refreshAccount(id: UUID, force: Bool) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        if accounts[index].isRefreshing {
            return
        }

        accounts[index].isRefreshing = true
        accounts[index].lastError = nil

        do {
            let refreshed = try await service.refreshAccount(accounts[index], force: force)
            accounts[index] = refreshed
        } catch {
            accounts[index].lastError = error.localizedDescription
            accounts[index].isRefreshing = false
        }

        save()
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                accounts = []
                return
            }

            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            accounts = try decoder.decode([AIUsageAccount].self, from: data).filter { account in
                guard account.provider == .codex else { return true }
                return (try? credentialStore.credentials(for: account)) != nil
            }
        } catch {
            accounts = []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(accounts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[AIUsageStore] Failed to save accounts: \(error)")
        }
    }
}

private actor AIUsageService {
    private let credentialStore = AIUsageCredentialStore.shared
    private let codexAuthClient = CodexAuthClient()
    private let codexUsageClient = CodexUsageClient()
    private let claudeCLI = ClaudeCLIClient()

    func refreshAccount(_ account: AIUsageAccount, force _: Bool) async throws -> AIUsageAccount {
        var refreshed = account

        switch account.provider {
        case .claude:
            refreshed.snapshot = try await claudeCLI.fetchUsage()
        case .codex:
            guard case let .codex(credentials) = try credentialStore.credentials(for: account) else {
                throw AIUsageError.requestFailed("Missing Codex credentials")
            }
            let updatedCredentials = try await codexAuthClient.ensureValidCredentials(credentials)
            try credentialStore.store(.codex(updatedCredentials), for: account)
            refreshed.snapshot = try await codexUsageClient.fetchUsage(credentials: updatedCredentials)
        }

        refreshed.lastError = nil
        refreshed.isRefreshing = false
        return refreshed
    }
}

private final class AIUsageCredentialStore {
    static let shared = AIUsageCredentialStore()

    private let service = "notchera.ai-usage"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func store(_ credentials: AIUsageCredentials, for account: AIUsageAccount) throws {
        switch credentials {
        case .claude:
            try removeCredentials(for: account)
        case let .codex(storedCredentials):
            let data = try encoder.encode(storedCredentials)
            let query = baseQuery(for: account)

            SecItemDelete(query as CFDictionary)

            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw AIUsageError.requestFailed("Failed to save credentials (\(status))")
            }
        }
    }

    func credentials(for account: AIUsageAccount) throws -> AIUsageCredentials {
        switch account.provider {
        case .claude:
            return .claude
        case .codex:
            var query = baseQuery(for: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status != errSecItemNotFound else {
                throw AIUsageError.requestFailed("Missing Codex credentials")
            }

            guard status == errSecSuccess,
                  let data = result as? Data
            else {
                throw AIUsageError.requestFailed("Failed to load credentials (\(status))")
            }

            return try .codex(decoder.decode(CodexStoredCredentials.self, from: data))
        }
    }

    func removeCredentials(for account: AIUsageAccount) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIUsageError.requestFailed("Failed to remove credentials (\(status))")
        }
    }

    private func baseQuery(for account: AIUsageAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account.provider.rawValue).\(account.id.uuidString)",
        ]
    }
}

private actor CodexAuthClient {
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let expiryLeeway: TimeInterval = 5 * 60
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func ensureValidCredentials(_ credentials: CodexStoredCredentials) async throws -> CodexStoredCredentials {
        guard Date().addingTimeInterval(expiryLeeway) >= credentials.expiresAt else {
            return credentials
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
            URLQueryItem(name: "client_id", value: clientID),
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let tokenResponse = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        guard let accessToken = tokenResponse.accessToken,
              let refreshToken = tokenResponse.refreshToken,
              let expiresIn = tokenResponse.expiresIn
        else {
            throw AIUsageError.invalidTokenResponse
        }

        let accountId = try CodexJWTDecoder.accountID(from: accessToken)
        return CodexStoredCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            accountId: accountId
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }
}

private actor CodexUsageClient {
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let session: URLSession

    init(session _: URLSession = .shared) {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func fetchUsage(credentials: CodexStoredCredentials) async throws -> AIUsageSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let usageResponse = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        return usageResponse.snapshot
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }
}

private struct CodexUsageResponse: Decodable {
    let rateLimit: CodexUsageRateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    var snapshot: AIUsageSnapshot {
        AIUsageSnapshot(
            fiveHour: rateLimit?.primaryWindow?.snapshot ?? .empty,
            weekly: rateLimit?.secondaryWindow?.snapshot ?? .empty,
            fetchedAt: Date()
        )
    }
}

private struct CodexUsageRateLimit: Decodable {
    let primaryWindow: CodexUsageWindow?
    let secondaryWindow: CodexUsageWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexUsageWindow: Decodable {
    let usedPercent: Double?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }

    var snapshot: AIUsageWindowSnapshot {
        let used = max(0, min(100, usedPercent ?? 0))
        return AIUsageWindowSnapshot(
            usedPercent: used,
            remainingPercent: max(0, 100 - used),
            resetAt: resetAt.map { Date(timeIntervalSince1970: $0) },
            resetDescription: nil
        )
    }
}

private struct CodexTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct CodexOAuthCredentials {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountId: String
}

private struct CodexAuthorizationState {
    var verifier: String
    var state: String
    var authorizationURL: URL
    var callbackServer: CodexCallbackServer
}

@MainActor
final class CodexLoginSession: ObservableObject {
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var authorizationURL: URL?
    @Published var manualInput = ""

    private let client = CodexBrowserAuthClient()
    private var authState: CodexAuthorizationState?

    func start() async throws {
        cancel()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let authState = try await client.startAuthorization()
        self.authState = authState
        authorizationURL = authState.authorizationURL
        NSWorkspace.shared.open(authState.authorizationURL)
    }

    func complete() async throws -> CodexStoredCredentials {
        try await finishLogin(manualInput: manualInput)
    }

    func completeFromCallbackOnly() async throws -> CodexStoredCredentials {
        try await finishLogin(manualInput: "")
    }

    private func finishLogin(manualInput: String) async throws -> CodexStoredCredentials {
        guard let authState else {
            throw AIUsageError.requestFailed("Login has not started yet")
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let credentials = try await client.completeAuthorization(state: authState, manualInput: manualInput)
        cancel()
        return CodexStoredCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            accountId: credentials.accountId
        )
    }

    func cancel() {
        authState?.callbackServer.cancel()
        authState = nil
        authorizationURL = nil
        manualInput = ""
    }
}

private actor CodexBrowserAuthClient {
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let redirectURL = URL(string: "http://localhost:1455/auth/callback")!
    private let scope = "openid profile email offline_access"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startAuthorization() async throws -> CodexAuthorizationState {
        let verifier = Self.makeCodeVerifier()
        let challenge = try Self.makeCodeChallenge(verifier: verifier)
        let state = Self.makeState()
        let callbackServer = try CodexCallbackServer(expectedState: state)

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "notchera"),
        ]

        guard let authorizationURL = components?.url else {
            callbackServer.cancel()
            throw AIUsageError.requestFailed("Failed to build Codex authorization URL")
        }

        return CodexAuthorizationState(
            verifier: verifier,
            state: state,
            authorizationURL: authorizationURL,
            callbackServer: callbackServer
        )
    }

    func completeAuthorization(state: CodexAuthorizationState, manualInput: String) async throws -> CodexOAuthCredentials {
        let code = try await state.callbackServer.waitForCode(manualInput: manualInput)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: state.verifier),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let tokenResponse = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        guard let accessToken = tokenResponse.accessToken,
              let refreshToken = tokenResponse.refreshToken,
              let expiresIn = tokenResponse.expiresIn
        else {
            throw AIUsageError.invalidTokenResponse
        }

        let accountId = try CodexJWTDecoder.accountID(from: accessToken)
        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            accountId: accountId
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIUsageError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIUsageError.requestFailed(message)
        }
    }

    private static func makeState() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func makeCodeVerifier() -> String {
        let bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(verifier: String) throws -> String {
        guard let data = verifier.data(using: .utf8) else {
            throw AIUsageError.requestFailed("Failed to encode PKCE verifier")
        }
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
}

private final class CodexCallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.notchera.codex-callback")
    private var resultContinuation: CheckedContinuation<String, Error>?
    private var isFinished = false

    init(expectedState: String) throws {
        self.expectedState = expectedState
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 1455)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    func waitForCode(manualInput: String) async throws -> String {
        if let code = Self.extractCode(from: manualInput, expectedState: expectedState) {
            finish(.success(code))
            return code
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.resultContinuation = continuation
        }
    }

    func cancel() {
        finish(.failure(AIUsageError.requestFailed("Login cancelled")))
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                return
            }
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? request
            guard let code = Self.extractCode(from: firstLine, expectedState: expectedState) else {
                return
            }
            respond(connection: connection)
            finish(.success(code))
        }
    }

    private func respond(connection: NWConnection) {
        let body = """
        <!doctype html>
        <html lang=\"en\">
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
        <title>Notchera</title>
        <style>
        :root {
            color-scheme: dark;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        }
        * {
            box-sizing: border-box;
        }
        html, body {
            margin: 0;
            min-height: 100%;
            background:
                radial-gradient(circle at top, rgba(255,255,255,0.12), transparent 36%),
                linear-gradient(180deg, #151517 0%, #0b0b0c 100%);
            color: #f5f5f7;
        }
        body {
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: 32px;
        }
        .card {
            width: min(100%, 460px);
            padding: 32px 30px;
            border-radius: 24px;
            background: rgba(255,255,255,0.06);
            border: 1px solid rgba(255,255,255,0.1);
            box-shadow: 0 24px 80px rgba(0,0,0,0.38);
            backdrop-filter: blur(18px);
            text-align: center;
        }
        .badge {
            width: 56px;
            height: 56px;
            margin: 0 auto 18px;
            border-radius: 18px;
            display: grid;
            place-items: center;
            font-size: 24px;
            background: linear-gradient(180deg, rgba(255,255,255,0.16), rgba(255,255,255,0.08));
            border: 1px solid rgba(255,255,255,0.12);
        }
        h1 {
            margin: 0;
            font-size: 28px;
            font-weight: 600;
            letter-spacing: -0.03em;
        }
        p {
            margin: 10px 0 0;
            font-size: 15px;
            line-height: 1.5;
            color: rgba(245,245,247,0.72);
        }
        .secondary {
            margin-top: 18px;
            font-size: 13px;
            color: rgba(245,245,247,0.48);
        }
        </style>
        </head>
        <body>
        <div class=\"card\">
            <div class=\"badge\">✓</div>
            <h1>notchera</h1>
            <p>successful. your codex account is now connected.</p>
            <p class=\"secondary\">you can return to the app now.</p>
        </div>
        <script>
        window.close();
        </script>
        </body>
        </html>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func finish(_ result: Result<String, Error>) {
        guard !isFinished else { return }
        isFinished = true
        listener.cancel()
        resultContinuation?.resume(with: result)
        resultContinuation = nil
    }

    private static func extractCode(from input: String, expectedState: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let raw: String = if trimmed.hasPrefix("GET "), let pathComponent = trimmed.split(separator: " ").dropFirst().first {
            "http://localhost\(pathComponent)"
        } else {
            trimmed
        }

        guard let url = URL(string: raw), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let state = components.queryItems?.first(where: { $0.name == "state" })?.value, state != expectedState {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }
}

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
    let authMethod: String?
    let apiProvider: String?
    let email: String?
    let orgId: String?
    let orgName: String?
    let subscriptionType: String?
}

private actor ClaudeCLIClient {
    func fetchUsage() async throws -> AIUsageSnapshot {
        let workingDirectory = try isolatedWorkingDirectory()

        let statusOutput = try runCommand(["auth", "status"], currentDirectoryURL: workingDirectory)
        let statusData = Data(statusOutput.utf8)
        let status = try JSONDecoder().decode(ClaudeAuthStatus.self, from: statusData)

        guard status.loggedIn else {
            throw AIUsageError.requestFailed("Claude Code is not logged in")
        }

        let usageOutput = try runPTYUsage(currentDirectoryURL: workingDirectory)
        return try ClaudeUsageParser.parse(usageOutput)
    }

    private func isolatedWorkingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchera-claude-usage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func runCommand(_ arguments: [String], currentDirectoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude"] + arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw AIUsageError.requestFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func runPTYUsage(currentDirectoryURL: URL) throws -> String {
        let script = #"""
        import os, pty, subprocess, select, time, sys
        cwd = sys.argv[1]
        master, slave = pty.openpty()
        proc = subprocess.Popen(['claude'], stdin=slave, stdout=slave, stderr=slave, text=False, cwd=cwd)
        os.close(slave)
        out = b''
        def drain(seconds):
            end = time.time() + seconds
            global out
            while time.time() < end:
                r,_,_ = select.select([master], [], [], 0.2)
                if master in r:
                    try:
                        data = os.read(master, 4096)
                    except OSError:
                        return
                    if not data:
                        return
                    out += data
        for _ in range(25):
            drain(0.25)
            if b'Claude Code' in out or b'/help' in out or b'Welcome back' in out or '❯'.encode() in out:
                break
        os.write(master, b'/usage\r')
        for _ in range(24):
            drain(0.25)
            low = out.lower()
            if b'current session' in low and b'current week' in low:
                break
        os.write(master, b'\x03')
        drain(1.0)
        try:
            proc.terminate()
        except Exception:
            pass
        sys.stdout.write(out.decode('utf-8', 'ignore'))
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, currentDirectoryURL.path]
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: data, encoding: .utf8) ?? ""

        guard !output.isEmpty else {
            throw AIUsageError.requestFailed("Failed to read Claude Code usage")
        }

        return output
    }
}

private enum ClaudeUsageParser {
    static func parse(_ output: String) throws -> AIUsageSnapshot {
        let cleaned = output.replacingOccurrences(of: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        let fiveHour = try parseSection(named: "Current session", in: cleaned)
        let weekly = try parseSection(named: "Current week", in: cleaned)
        return AIUsageSnapshot(fiveHour: fiveHour, weekly: weekly, fetchedAt: Date())
    }

    private static func parseSection(named name: String, in text: String) throws -> AIUsageWindowSnapshot {
        let compactSource = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let compactName = name.replacingOccurrences(of: " ", with: "")

        guard let startRange = compactSource.range(of: compactName) else {
            throw AIUsageError.requestFailed("Could not parse Claude usage section: \(name)")
        }

        let remainingText = String(compactSource[startRange.lowerBound...])
        let sectionBody: String = if let nextRange = remainingText.dropFirst().range(of: "Current") {
            String(remainingText[..<nextRange.lowerBound])
        } else {
            remainingText
        }

        let usedPercent = parseCompactPercent(from: sectionBody)
        let resetDescription = parseCompactReset(from: sectionBody)
        return AIUsageWindowSnapshot(
            usedPercent: usedPercent,
            remainingPercent: max(0, 100 - usedPercent),
            resetAt: nil,
            resetDescription: resetDescription
        )
    }

    private static func parseCompactPercent(from text: String) -> Double {
        let regex = try? NSRegularExpression(pattern: #"(\d+)%used"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange])
        else {
            return 0
        }
        return value
    }

    private static func parseCompactReset(from text: String) -> String {
        guard let resetRange = text.range(of: "Rese") else {
            return "reset unknown"
        }
        var value = String(text[resetRange.lowerBound...])
        value = value.replacingOccurrences(of: #"^Reses?|^Resets"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\d+%used.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"What'?scontributing.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"Approximate,.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"Scanninglocalsessions.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"Extrausage.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(Europe/Istanbul)", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let weeklyMatch = value.range(of: #"([A-Za-z]{3})(\d{1,2})at([^A-Z]+(?:am|pm))"#, options: .regularExpression) {
            let matched = String(value[weeklyMatch])
            let regex = try? NSRegularExpression(pattern: #"([A-Za-z]{3})(\d{1,2})at([^A-Z]+(?:am|pm))"#)
            let nsRange = NSRange(matched.startIndex..., in: matched)
            if let match = regex?.firstMatch(in: matched, range: nsRange),
               let monthRange = Range(match.range(at: 1), in: matched),
               let dayRange = Range(match.range(at: 2), in: matched),
               let timeRange = Range(match.range(at: 3), in: matched)
            {
                let month = monthNumber(String(matched[monthRange]))
                let day = String(matched[dayRange]).leftPadding(toLength: 2, withPad: "0")
                let time = String(matched[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return "resets \(day)/\(month) \(time)"
            }
        }

        if let currentMatch = value.range(of: #"([0-9]{1,2}(?::[0-9]{2})?(?:am|pm))"#, options: .regularExpression) {
            return "resets \(String(value[currentMatch]))"
        }

        if !value.isEmpty {
            return "resets \(value)"
        }

        return "reset unknown"
    }

    private static func monthNumber(_ month: String) -> String {
        switch month.lowercased() {
        case "jan": "01"
        case "feb": "02"
        case "mar": "03"
        case "apr": "04"
        case "may": "05"
        case "jun": "06"
        case "jul": "07"
        case "aug": "08"
        case "sep": "09"
        case "oct": "10"
        case "nov": "11"
        case "dec": "12"
        default: "--"
        }
    }
}

private enum CodexJWTDecoder {
    static func accountID(from accessToken: String) throws -> String {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let auth = payload["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String,
              !accountId.isEmpty
        else {
            throw AIUsageError.requestFailed("Failed to extract account ID")
        }

        return accountId
    }
}

private enum AIUsageError: LocalizedError {
    case invalidResponse
    case invalidTokenResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from server"
        case .invalidTokenResponse:
            "Server returned an incomplete token response"
        case let .requestFailed(message):
            message
        }
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        if count >= toLength {
            return self
        }
        return String(repeating: String(character), count: toLength - count) + self
    }
}

private func formURLEncodedData(_ items: [URLQueryItem]) -> Data? {
    var components = URLComponents()
    components.queryItems = items
    return components.percentEncodedQuery?.data(using: .utf8)
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
