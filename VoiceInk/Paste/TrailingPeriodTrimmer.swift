import Foundation
import NaturalLanguage

/// A lone dictated sentence reads as curt in chat when it ends in a period
/// ("Okay." against "Okay"), so the final period comes off. Anything longer is
/// prose and keeps its punctuation, and every period inside a sentence stays put.
enum TrailingPeriodTrimmer {
    /// Punctuation that legitimately closes a sentence after its period, such as
    /// `**Done.**` or `He said "no."`. The period behind it is still the terminator.
    private static let closingCharacters: Set<Character> = ["*", "_", "`", "\"", "'", ")", "]", "\u{201D}", "\u{2019}"]

    static func trim(_ text: String) -> String {
        // Multi-line output is a list or several paragraphs, never a single remark.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).contains("\n") else { return text }

        var characters = Array(text)
        var index = characters.count - 1
        while index >= 0, characters[index].isWhitespace || closingCharacters.contains(characters[index]) {
            index -= 1
        }

        // Only a plain period goes: "?", "!" and a trailing "..." all carry tone.
        guard index >= 1, characters[index] == ".", characters[index - 1] != ".",
            !isAbbreviation(characters, endingAt: index),
            isSingleSentence(String(characters[...index]))
        else { return text }

        characters.remove(at: index)
        return String(characters)
    }

    /// A final period the word itself needs — "the U.S.", "at 5 p.m." — is spelling,
    /// not tone, so it stays. Recognised by the initials it is built from, which keeps
    /// "example.com." and "5.5." out: those are ordinary words wearing a terminator.
    private static func isAbbreviation(_ characters: [Character], endingAt index: Int) -> Bool {
        var start = index - 1
        while start >= 0, !characters[start].isWhitespace { start -= 1 }

        let word = String(characters[(start + 1)..<index])
        guard word.contains(".") else { return false }

        return word.components(separatedBy: ".").allSatisfy { $0.count <= 2 && $0.allSatisfy(\.isLetter) }
    }

    private static func isSingleSentence(_ text: String) -> Bool {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if !text[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
            return count < 2
        }

        return count == 1
    }
}
