import Testing

@testable import VoiceInk

struct TrailingPeriodTrimmerTests {

    @Test(arguments: [
        ("Okay.", "Okay"),
        ("I'll send it over.", "I'll send it over"),
        ("Send it to Dr. Smith.", "Send it to Dr. Smith"),
        ("The total is 5.5.", "The total is 5.5"),
        ("He said \"no\".", "He said \"no\""),
        ("See the attachment (page 2).", "See the attachment (page 2)"),
        ("Check out https://example.com.", "Check out https://example.com"),
        ("**Done.**", "**Done**"),
        ("Okay. ", "Okay "),
    ])
    func stripsThePeriodOfALoneSentence(input: String, expected: String) {
        #expect(TrailingPeriodTrimmer.trim(input) == expected)
    }

    @Test(arguments: [
        "Sure",
        "I'll send it over. Let me know if you need anything.",
        "Are you free?",
        "No way!",
        "Let me think...",
        "He's from the U.S.",
        "See you at 5 p.m.",
        "Line one.\nLine two.",
        "\u{5B8C}\u{6210}\u{4E86}\u{3002}",
        "Okay. \u{1F642}",
    ])
    func leavesEverythingElseAlone(input: String) {
        #expect(TrailingPeriodTrimmer.trim(input) == input)
    }

    @Test func trimsEachSplitMessageOnItsOwn() {
        let messages = MessageSplitter.split("Hey.\n\nAre you around?\n\nI'll call you. It won't take long.")
            .map(TrailingPeriodTrimmer.trim)

        #expect(messages == ["Hey", "Are you around?", "I'll call you. It won't take long."])
    }
}
