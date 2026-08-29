import AppKit
import ApplicationServices
import Foundation

/// Reads the text of the system-wide focused UI element so paste and send operations
/// can be confirmed instead of guessed at with fixed delays. Every read returns `nil`
/// when the focused element does not expose its text — common in Electron apps and
/// some web views — which lets callers fall back to a delay.
enum FocusedFieldReader {
    /// Keeps a hung target app from stalling the caller for the multi-second default.
    private static let messagingTimeout: Float = 0.2
    private static let pollInterval: TimeInterval = 0.05

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }()

    static func focusedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = focusedElement() else { return nil }
        return stringValue(of: element, attribute: kAXValueAttribute)
    }

    /// Polls until the focused field contains `text`, confirming a paste landed.
    /// Returns `false` if the field is unreadable or the timeout elapses.
    static func waitForText(_ text: String, timeout: TimeInterval) async -> Bool {
        await poll(timeout: timeout) { $0.contains(text) }
    }

    /// Polls until the focused field is empty, confirming a sent message cleared the
    /// composer. Returns `false` if the field is unreadable or the timeout elapses.
    static func waitForEmptyField(timeout: TimeInterval) async -> Bool {
        await poll(timeout: timeout) { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func poll(timeout: TimeInterval, until condition: (String) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            guard let current = focusedText() else { return false }
            if condition(current) { return true }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date() < deadline
        return false
    }

    private static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func stringValue(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
