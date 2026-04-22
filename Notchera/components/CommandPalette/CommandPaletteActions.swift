import AppKit
import Defaults
import IOKit.pwr_mgt
import SwiftUI

enum CommandPaletteAction {
    case copyToClipboard(String)
    case googleSearch(String)
    case togglePreventSleep
    case enablePreventSleep(duration: TimeInterval)
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

        do {
            var parser = Parser(input: trimmedExpression)
            let value = try parser.parse()
            guard value.isFinite else { return nil }
            return CalculatorResult(value: value)
        } catch {
            return nil
        }
    }

    private static func shouldTreatAsCalculation(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.contains(where: \.isNumber) else { return false }

        let operatorCount = characters.count(where: { "+-*/()%".contains($0) })
        if operatorCount > 0 {
            return true
        }

        if value.contains("(") || value.contains(")") {
            return true
        }

        let decimalSeparatorCount = characters.count(where: { $0 == "." })
        return decimalSeparatorCount == 1 && characters.allSatisfy { $0.isNumber || $0 == "." }
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

    private struct Parser {
        let input: [Character]
        var index = 0

        init(input: String) {
            self.input = Array(input.filter { !$0.isWhitespace })
        }

        mutating func parse() throws -> Double {
            guard !input.isEmpty else { throw ParserError.invalidExpression }
            let value = try parseExpression()
            guard index == input.count else { throw ParserError.invalidExpression }
            return value
        }

        private mutating func parseExpression() throws -> Double {
            var value = try parseTerm()

            while let token = currentToken {
                if token == "+" {
                    index += 1
                    value += try parseTerm()
                } else if token == "-" {
                    index += 1
                    value -= try parseTerm()
                } else {
                    break
                }
            }

            return value
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseFactor()

            while let token = currentToken {
                if token == "*" {
                    index += 1
                    value *= try parseFactor()
                } else if token == "/" {
                    index += 1
                    value /= try parseFactor()
                } else if token == "%" {
                    index += 1
                    try value.formTruncatingRemainder(dividingBy: parseFactor())
                } else {
                    break
                }
            }

            return value
        }

        private mutating func parseFactor() throws -> Double {
            guard let token = currentToken else { throw ParserError.invalidExpression }

            if token == "+" {
                index += 1
                return try parseFactor()
            }

            if token == "-" {
                index += 1
                return try -parseFactor()
            }

            if token == "(" {
                index += 1
                let value = try parseExpression()
                guard currentToken == ")" else { throw ParserError.invalidExpression }
                index += 1
                return value
            }

            return try parseNumber()
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
            let stringValue = String(input[startIndex ..< index])
            guard let value = Double(stringValue) else { throw ParserError.invalidExpression }
            return value
        }

        private var currentToken: Character? {
            index < input.count ? input[index] : nil
        }
    }

    private enum ParserError: Error {
        case invalidExpression
    }
}
