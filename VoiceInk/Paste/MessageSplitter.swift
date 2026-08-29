import Foundation

/// Splits dictated text into individual chat messages for modes that send each
/// message separately. Blank-line separated blocks are preferred, falling back to
/// single line breaks, so AI prompts can emit either shape.
enum MessageSplitter {
    private static let maximumMessageCount = 20
    private static let preambleCharacterLimit = 80

    static func split(_ text: String) -> [String] {
        let paragraphs = segments(in: text, separatedBy: "\n\n")
        let messages = paragraphs.count > 1 ? paragraphs : segments(in: text, separatedBy: "\n")

        guard messages.count > 1, messages.count <= maximumMessageCount else { return [text] }
        return droppingPreamble(from: messages)
    }

    private static func segments(in text: String, separatedBy separator: String) -> [String] {
        text.components(separatedBy: separator)
            .map(normalized)
            .filter { !$0.isEmpty && !isDecoration($0) }
    }

    /// Models like to fence their answer or separate it with a rule. Those lines are
    /// never something the user dictated, so they never become a message.
    private static func isDecoration(_ text: String) -> Bool {
        if text.hasPrefix("```") { return true }
        let rules: Set<Character> = ["-", "*", "_", "="]
        return text.count >= 3 && text.allSatisfy { rules.contains($0) }
    }

    /// Drops a lead-in like "Here's the polished version:" that the model added of its
    /// own accord. Kept deliberately narrow — a short opener ending in a colon, and only
    /// when real messages follow it — because a wrong guess silently eats a message.
    private static func droppingPreamble(from messages: [String]) -> [String] {
        guard messages.count > 2, let first = messages.first,
            first.hasSuffix(":"), first.count <= preambleCharacterLimit
        else {
            return messages
        }

        return Array(messages.dropFirst())
    }

    /// Trims decoration at the edges of a block as well, since a rule the model emitted
    /// directly above its first message would otherwise ride along into that message.
    private static func normalized(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        while let first = lines.first, first.isEmpty || isDecoration(first) { lines.removeFirst() }
        while let last = lines.last, last.isEmpty || isDecoration(last) { lines.removeLast() }

        return lines.joined(separator: "\n")
    }
}
