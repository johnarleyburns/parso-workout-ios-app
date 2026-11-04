import Foundation

/// Which Set Card value a numeric entry sheet edits.
public enum WatchNumericField: Sendable, Equatable {
    case weight, reps
}

/// Pure keypad reducer for the Watch numeric entry sheet. Reps admit digits only; weight admits one
/// decimal separator and at most two fraction digits. Invalid keys leave the text unchanged.
public enum WatchNumericKeypad {
    public static let keys: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
    public static let maxIntegerDigits = 4
    public static let maxFractionDigits = 2

    public static func apply(_ key: String, to text: String, field: WatchNumericField) -> String {
        if key == "⌫" { return String(text.dropLast()) }
        if key == "." {
            guard field == .weight, !text.contains(".") else { return text }
            return text.isEmpty ? "0." : text + "."
        }
        guard key.count == 1, let ch = key.first, ("0"..."9").contains(ch) else { return text }
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...]
            return fraction.count < maxFractionDigits ? text + key : text
        }
        if text == "0" { return key } // no leading zeros
        let limit = field == .weight ? maxIntegerDigits : 3
        return text.count < limit ? text + key : text
    }
}

/// Deterministic, bounded English spoken-number grammar: "eight" → "8", "ten point two five" → "10.25",
/// "one hundred twenty five" → "125". Anything else (prose, negatives, non-finite words) is nil.
/// Only English is supported; other locales' number words are intentionally rejected, not guessed.
public enum WatchSpokenNumber {
    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
        "ninety": 90
    ]

    public static func normalize(_ raw: String) -> String? {
        let tokens = raw.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let separators: Set<String> = ["point", "dot"]
        let split = tokens.firstIndex(where: { separators.contains($0) })
        let integerTokens = split.map { Array(tokens[..<$0]) } ?? tokens
        let fractionTokens = split.map { Array(tokens[($0 + 1)...]) }

        var integer: Int?
        if !integerTokens.isEmpty {
            guard let parsed = parseInteger(integerTokens) else { return nil }
            integer = parsed
        } else if fractionTokens == nil {
            return nil
        }
        var result = String(integer ?? 0)
        if let fractionTokens {
            guard !fractionTokens.isEmpty else { return nil }
            var digits = ""
            for token in fractionTokens {
                guard let digit = ones[token] else { return nil }
                digits += String(digit)
            }
            result += "." + digits
        }
        return result
    }

    private static func parseInteger(_ tokens: [String]) -> Int? {
        var total = 0
        var chunk = 0 // value below 100 being built
        var sawHundred = false
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let n = ones[token] {
                guard chunk == 0 || (chunk % 10 == 0 && chunk >= 20) else { return nil }
                if n == 0 && (tokens.count > 1) { return nil }
                chunk += n
            } else if let n = teens[token] {
                guard chunk == 0 else { return nil }
                chunk = n
            } else if let n = tens[token] {
                guard chunk == 0 else { return nil }
                chunk = n
            } else if token == "hundred" {
                guard !sawHundred, index > 0, (1...9).contains(chunk) else { return nil }
                total = chunk * 100
                chunk = 0
                sawHundred = true
            } else if token == "and", sawHundred, index + 1 < tokens.count {
                // "one hundred and five"
            } else {
                return nil
            }
            index += 1
        }
        return total + chunk
    }
}
