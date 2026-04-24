import AppKit
import Defaults
import Darwin
import IOKit.pwr_mgt
import SwiftUI

enum CommandPaletteAction {
    case copyToClipboard(String)
    case googleSearch(String)
    case togglePreventSleep
    case enablePreventSleep(duration: TimeInterval)
    case lockScreen
    case sleepMac
}

@MainActor
final class CommandPaletteSystemActions {
    static func lockScreen() async {
        typealias LockScreenFunction = @convention(c) () -> Void

        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else {
            return
        }

        let lock = unsafeBitCast(symbol, to: LockScreenFunction.self)
        lock()
        dlclose(handle)
    }

    static func sleepMac() async {
        runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
    }

    private static func runProcess(_ launchPath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try? process.run()
    }
}

@MainActor
final class PreventSleepManager: ObservableObject {
    static let shared = PreventSleepManager()

    @Published private(set) var isActive = false
    @Published private(set) var expiresAt: Date?

    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var expiryTask: Task<Void, Never>?

    private init() {
        restoreIfNeeded()
    }

    var statusText: String {
        guard isActive else { return "Currently off" }
        guard let expiresAt else { return "Currently on" }

        let remaining = max(0, expiresAt.timeIntervalSinceNow)
        return "On for \(durationLabel(for: remaining)) more"
    }

    func toggle() {
        if isActive {
            disable()
        } else {
            enable(for: nil)
        }
    }

    func enable(for duration: TimeInterval?) {
        disableAssertions()
        createAssertions()

        let clampedDuration = duration.map { max(1, $0) }
        let nextExpiry = clampedDuration.map { Date().addingTimeInterval($0) }

        isActive = true
        expiresAt = nextExpiry
        persistState()
        scheduleExpiryIfNeeded()
    }

    func disable() {
        expiryTask?.cancel()
        expiryTask = nil
        disableAssertions()
        isActive = false
        expiresAt = nil
        persistState()
    }

    private func restoreIfNeeded() {
        guard Defaults[.preventSleepEnabled] else { return }

        let storedExpiry = Defaults[.preventSleepExpiresAt].flatMap { timestamp in
            timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }

        if let storedExpiry, storedExpiry <= .now {
            Defaults[.preventSleepEnabled] = false
            Defaults[.preventSleepExpiresAt] = nil
            return
        }

        let remainingDuration = storedExpiry.map(\.timeIntervalSinceNow)
        enable(for: remainingDuration)
    }

    private func createAssertions() {
        let assertionName = "Notchera Prevent Sleep" as CFString
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), assertionName, &idleSleepAssertionID)
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), assertionName, &displaySleepAssertionID)
    }

    private func disableAssertions() {
        if idleSleepAssertionID != 0 {
            IOPMAssertionRelease(idleSleepAssertionID)
            idleSleepAssertionID = 0
        }

        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
    }

    private func scheduleExpiryIfNeeded() {
        expiryTask?.cancel()
        expiryTask = nil

        guard let expiresAt else { return }

        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = expiresAt.timeIntervalSinceNow
                if remaining <= 0 {
                    await MainActor.run {
                        self?.disable()
                    }
                    return
                }

                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    guard let self, self.isActive else { return }
                    self.objectWillChange.send()
                }
            }
        }
    }

    private func persistState() {
        Defaults[.preventSleepEnabled] = isActive
        Defaults[.preventSleepExpiresAt] = expiresAt?.timeIntervalSince1970
    }

    private func durationLabel(for duration: TimeInterval) -> String {
        let roundedDuration = max(60, Int(duration.rounded()))
        let hours = roundedDuration / 3600
        let minutes = (roundedDuration % 3600) / 60

        if roundedDuration >= 3600, minutes == 0 {
            return "\(hours)H"
        }

        if roundedDuration < 3600 {
            return "\(max(1, roundedDuration / 60))M"
        }

        return "\(hours)H \(minutes)M"
    }
}

enum CalculatorEvaluator {
    static func evaluate(_ expression: String) -> CalculatorResult? {
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExpression.isEmpty else { return nil }
        guard shouldTreatAsCalculation(trimmedExpression) else { return nil }

        if let conversionResult = UnitConverter.evaluate(trimmedExpression) {
            return conversionResult
        }

        do {
            var parser = Parser(input: trimmedExpression)
            let value = try parser.parse()
            guard value.value.isFinite else { return nil }
            return CalculatorResult(value: value.value)
        } catch {
            return nil
        }
    }

    private static func shouldTreatAsCalculation(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains(where: \.isNumber)
            || normalized.contains("pi")
            || normalized.contains("sqrt")
            || normalized.contains("abs")
            || normalized.contains("round")
            || normalized.contains("floor")
            || normalized.contains("ceil")
    }

    struct CalculatorResult {
        let value: Double

        var displayValue: String {
            if value.rounded(.towardZero) == value {
                return String(Int64(value))
            }

            return value.formatted(.number.precision(.fractionLength(0 ... 8)))
        }
    }

    private struct Value {
        let value: Double
        let isPercent: Bool

        init(_ value: Double, isPercent: Bool = false) {
            self.value = value
            self.isPercent = isPercent
        }
    }

    private struct Parser {
        let input: [Character]
        var index = 0

        init(input: String) {
            let normalized = input
                .replacingOccurrences(of: " of ", with: " * ", options: .caseInsensitive)
                .replacingOccurrences(of: " of", with: " *", options: .caseInsensitive)
                .replacingOccurrences(of: "of ", with: "* ", options: .caseInsensitive)
            self.input = Array(normalized.filter { !$0.isWhitespace })
        }

        mutating func parse() throws -> Value {
            guard !input.isEmpty else { throw ParserError.invalidExpression }
            let value = try parseExpression()
            guard index == input.count else { throw ParserError.invalidExpression }
            return value
        }

        private mutating func parseExpression() throws -> Value {
            var lhs = try parseTerm()

            while let token = currentToken, token == "+" || token == "-" {
                index += 1
                let rhs = try parseTerm()

                if token == "+" {
                    lhs = rhs.isPercent
                        ? Value(lhs.value + (lhs.value * rhs.value))
                        : Value(lhs.value + rhs.value)
                } else {
                    lhs = rhs.isPercent
                        ? Value(lhs.value - (lhs.value * rhs.value))
                        : Value(lhs.value - rhs.value)
                }
            }

            return lhs
        }

        private mutating func parseTerm() throws -> Value {
            var lhs = try parsePower()

            while true {
                if let token = currentToken, token == "*" || token == "/" || token == "%" {
                    index += 1
                    let rhs = try parsePower()

                    switch token {
                    case "*":
                        lhs = Value(lhs.value * rhs.value)
                    case "/":
                        lhs = Value(lhs.value / rhs.value)
                    case "%":
                        lhs = Value(lhs.value.truncatingRemainder(dividingBy: rhs.value))
                    default:
                        break
                    }

                    continue
                }

                if shouldImplicitlyMultiply {
                    let rhs = try parsePower()
                    lhs = Value(lhs.value * rhs.value)
                    continue
                }

                break
            }

            return lhs
        }

        private mutating func parsePower() throws -> Value {
            var lhs = try parseUnary()

            while currentToken == "^" {
                index += 1
                let rhs = try parseUnary()
                lhs = Value(pow(lhs.value, rhs.value))
            }

            return lhs
        }

        private mutating func parseUnary() throws -> Value {
            guard let token = currentToken else { throw ParserError.invalidExpression }

            if token == "+" {
                index += 1
                return try parseUnary()
            }

            if token == "-" {
                index += 1
                let value = try parseUnary()
                return Value(-value.value, isPercent: value.isPercent)
            }

            if token == "%" {
                index += 1
                let value = try parseUnary()
                return Value(value.value / 100, isPercent: true)
            }

            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Value {
            guard let token = currentToken else { throw ParserError.invalidExpression }

            if token == "(" {
                index += 1
                let value = try parseExpression()
                guard currentToken == ")" else { throw ParserError.invalidExpression }
                index += 1
                return applyPostfixPercentIfNeeded(to: value)
            }

            if token.isLetter {
                let identifier = try parseIdentifier()

                if let constant = constantValue(for: identifier) {
                    return applyPostfixPercentIfNeeded(to: Value(constant))
                }

                guard currentToken == "(" else { throw ParserError.invalidExpression }
                index += 1
                let argument = try parseExpression()
                guard currentToken == ")" else { throw ParserError.invalidExpression }
                index += 1

                let result = try evaluateFunction(identifier, argument: argument.value)
                return applyPostfixPercentIfNeeded(to: Value(result))
            }

            return applyPostfixPercentIfNeeded(to: Value(try parseNumber()))
        }

        private mutating func parseIdentifier() throws -> String {
            let startIndex = index
            while let token = currentToken, token.isLetter {
                index += 1
            }

            guard startIndex != index else { throw ParserError.invalidExpression }
            return String(input[startIndex ..< index]).lowercased()
        }

        private mutating func parseNumber() throws -> Double {
            let startIndex = index
            var hasDecimalPoint = false

            while let token = currentToken {
                if token.isNumber {
                    index += 1
                    continue
                }

                if token == ".", !hasDecimalPoint {
                    hasDecimalPoint = true
                    index += 1
                    continue
                }

                break
            }

            guard startIndex != index else { throw ParserError.invalidExpression }

            if let token = currentToken, token == "e" || token == "E" {
                let exponentMarkerIndex = index
                index += 1

                if let sign = currentToken, sign == "+" || sign == "-" {
                    index += 1
                }

                let exponentStart = index
                while let token = currentToken, token.isNumber {
                    index += 1
                }

                if exponentStart == index {
                    index = exponentMarkerIndex
                }
            }

            let stringValue = String(input[startIndex ..< index])
            guard let value = Double(stringValue) else { throw ParserError.invalidExpression }

            if let suffix = currentToken,
               let normalizedSuffix = String(suffix).lowercased().first,
               let multiplier = suffixMultiplier(for: normalizedSuffix)
            {
                index += 1
                return value * multiplier
            }

            return value
        }

        private func constantValue(for identifier: String) -> Double? {
            switch identifier {
            case "pi":
                Double.pi
            case "e":
                M_E
            default:
                nil
            }
        }

        private func evaluateFunction(_ identifier: String, argument: Double) throws -> Double {
            switch identifier {
            case "sqrt":
                sqrt(argument)
            case "abs":
                abs(argument)
            case "round":
                argument.rounded()
            case "floor":
                floor(argument)
            case "ceil":
                ceil(argument)
            default:
                throw ParserError.invalidExpression
            }
        }

        private func suffixMultiplier(for suffix: Character) -> Double? {
            switch suffix {
            case "k":
                1_000
            case "m":
                1_000_000
            case "b":
                1_000_000_000
            default:
                nil
            }
        }

        private mutating func applyPostfixPercentIfNeeded(to value: Value) -> Value {
            guard currentToken == "%" else { return value }
            index += 1
            return Value(value.value / 100, isPercent: true)
        }

        private var shouldImplicitlyMultiply: Bool {
            guard let token = currentToken else { return false }
            return token == "(" || token.isLetter || token.isNumber || token == "." || token == "%"
        }

        private var currentToken: Character? {
            index < input.count ? input[index] : nil
        }
    }

    private enum UnitConverter {
        private static let factors: [String: Double] = [
            "bit": 1, "bits": 1,
            "b": 8, "byte": 8, "bytes": 8,
            "kb": 8 * 1024,
            "mb": 8 * 1024 * 1024,
            "gb": 8 * 1024 * 1024 * 1024,
            "tb": 8 * 1024 * 1024 * 1024 * 1024,
            "pb": 8 * 1024 * 1024 * 1024 * 1024 * 1024,
            "kbit": 1024,
            "mbit": 1024 * 1024,
            "gbit": 1024 * 1024 * 1024,
            "tbit": 1024 * 1024 * 1024 * 1024,
            "pbit": 1024 * 1024 * 1024 * 1024 * 1024,
            "kib": 8 * 1024,
            "mib": 8 * 1024 * 1024,
            "gib": 8 * 1024 * 1024 * 1024,
            "tib": 8 * 1024 * 1024 * 1024 * 1024,
            "pib": 8 * 1024 * 1024 * 1024 * 1024 * 1024
        ]

        static func evaluate(_ input: String) -> CalculatorResult? {
            let normalized = input
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: "bytes", with: "byte")
                .replacingOccurrences(of: "bits", with: "bit")

            let separator: String
            if normalized.contains(" to ") {
                separator = " to "
            } else if normalized.contains(" in ") {
                separator = " in "
            } else {
                return nil
            }

            let parts = normalized.components(separatedBy: separator)
            guard parts.count == 2 else { return nil }

            let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let targetUnit = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let targetFactor = canonicalFactor(for: targetUnit) else { return nil }

            let leftParts = left.split(separator: " ")
            guard leftParts.count >= 2 else { return nil }
            guard let amount = Double(leftParts[0]) else { return nil }
            let sourceUnit = leftParts.dropFirst().joined(separator: " ")
            guard let sourceFactor = canonicalFactor(for: sourceUnit) else { return nil }

            let bits = amount * sourceFactor
            return CalculatorResult(value: bits / targetFactor)
        }

        private static func canonicalFactor(for unit: String) -> Double? {
            let cleaned = unit.replacingOccurrences(of: " ", with: "")
            if let factor = factors[cleaned] {
                return factor
            }

            switch cleaned {
            case "byte":
                return 8
            case "bit":
                return 1
            default:
                return nil
            }
        }
    }

    private enum ParserError: Error {
        case invalidExpression
    }
}
