import AppKit
import Carbon
import Foundation
import os

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    private static let prePasteDelay: TimeInterval = 0.10
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.25
    private static let pasteConfirmationTimeout: TimeInterval = 1.0
    private static let composerClearTimeout: TimeInterval = 1.0
    private static let unconfirmedSendDelay: TimeInterval = 0.50
    private static let interMessageDelay: TimeInterval = 0.30

    private struct PasteSessionOutcome {
        let result: PasteResult
        let sessionID: String
    }

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<PasteResult, Never> {
        Task { @MainActor in
            await performPasteSession(text).result
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    /// Pass `restoresClipboard: false` when the caller pastes repeatedly and owns the
    /// snapshot and restore for the whole batch; restoring after every paste would
    /// discard the user's original clipboard.
    @MainActor
    private static func performPasteSession(
        _ text: String,
        restoresClipboard: Bool = true
    ) async -> PasteSessionOutcome {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents =
            restoresClipboard && shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
        let sessionID = UUID().uuidString

        guard
            ClipboardManager.setClipboard(
                text,
                transient: shouldRestoreClipboard,
                sessionID: shouldRestoreClipboard ? sessionID : nil
            )
        else {
            logger.error("Failed to prepare clipboard for paste")
            return PasteSessionOutcome(result: .commandNotPosted, sessionID: sessionID)
        }

        await wait(prePasteDelay)

        let pasteResult = await postPasteCommand()
        if restoresClipboard && shouldRestoreClipboard {
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                on: pasteboard
            )
        }

        return PasteSessionOutcome(result: pasteResult, sessionID: sessionID)
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    @MainActor
    private static func postPasteCommand() async -> PasteResult {
        if PasteMethod.current() == .appleScript {
            return pasteUsingAppleScript() ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard()
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard
    ) {
        let delay = max(
            UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
            minimumClipboardRestoreDelay
        )

        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID)
            else {
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText
            && pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript(
        "tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode = makeScript(
        "tell application \"System Events\" to key code 9 using command down")

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("AppleScript paste script is unavailable")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript paste failed: \(String(describing: error), privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard() async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else {
            logger.error("Failed to create Cmd+V keyboard events")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vUp.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Auto Send Keys

    /// Pastes each message and posts the send key after every one, waiting for the
    /// focused field to reflect the paste before sending so the send key cannot
    /// outrun the text.
    @MainActor
    static func pasteAndSend(_ messages: [String], autoSendKey: AutoSendKey) async {
        guard let firstMessage = messages.first else { return }

        guard messages.count > 1 else {
            let outcome = await performPasteSession(firstMessage)
            await send(autoSendKey, after: firstMessage, pasteResult: outcome.result)
            return
        }

        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
        var lastSession: (text: String, id: String)?

        for (index, message) in messages.enumerated() {
            if index > 0, !(await FocusedFieldReader.waitForEmptyField(timeout: composerClearTimeout)) {
                await wait(interMessageDelay)
            }

            let outcome = await performPasteSession(message, restoresClipboard: false)
            lastSession = (message, outcome.sessionID)

            guard outcome.result.didPostPasteCommand else {
                logger.error("Stopping multi-message send after a failed paste")
                break
            }

            await send(autoSendKey, after: message, pasteResult: outcome.result)
        }

        if shouldRestoreClipboard, let lastSession {
            scheduleClipboardRestore(
                savedContents,
                expectedText: lastSession.text,
                sessionID: lastSession.id,
                on: pasteboard
            )
        }
    }

    /// Waits for the pasted text to appear in the focused field before posting the send
    /// key, so the send cannot outrun the paste. Falls back to a fixed delay when the
    /// field's text cannot be read.
    @MainActor
    private static func send(_ autoSendKey: AutoSendKey, after message: String, pasteResult: PasteResult) async {
        guard autoSendKey.isEnabled, pasteResult.didPostPasteCommand else { return }

        if !(await FocusedFieldReader.waitForText(message, timeout: pasteConfirmationTimeout)) {
            await wait(unconfirmedSendDelay)
        }

        performAutoSend(autoSendKey)
    }

    static func performAutoSend(_ key: AutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
