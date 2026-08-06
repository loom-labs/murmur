import Foundation
import Testing

@testable import BeagleCore

@Suite("Text chunker")
struct TextChunkerTests {

    // MARK: - Degenerate input

    @Test("Empty and whitespace-only input yields no chunks")
    func emptyInput() {
        #expect(TextChunker.chunk("").isEmpty)
        #expect(TextChunker.chunk("   \n\n  \t ").isEmpty)
    }

    @Test("A single short sentence is one chunk")
    func singleSentence() {
        #expect(TextChunker.chunk("Hello there.") == ["Hello there."])
    }

    @Test("Text with no terminator is still spoken")
    func noTerminator() {
        #expect(TextChunker.chunk("just a fragment") == ["just a fragment"])
    }

    // MARK: - Normalization

    @Test("Runs of whitespace collapse to single spaces")
    func collapsesWhitespace() {
        #expect(TextChunker.chunk("Hello    \t  there.") == ["Hello there."])
    }

    @Test("Paragraph breaks split even without punctuation")
    func paragraphBreakSplits() {
        // A heading with no trailing period must not run into the paragraph
        // below it. Both sides are kept above the short-fragment threshold so
        // this measures paragraph splitting and nothing else.
        let chunks = TextChunker.chunk(
            "Chapter One: The Beginning Of It All\n\nIt was a dark and stormy night.",
            maximumLength: 40
        )
        #expect(chunks == ["Chapter One: The Beginning Of It All", "It was a dark and stormy night."])
    }

    // MARK: - Sentence boundaries

    @Test("Sentences split on terminators and keep them")
    func splitsOnTerminators() {
        let chunks = TextChunker.chunk(
            "The first sentence ends here. The second one shouts! And the third asks?",
            maximumLength: 30
        )
        #expect(
            chunks == [
                "The first sentence ends here.",
                "The second one shouts!",
                "And the third asks?",
            ]
        )
    }

    @Test("Trailing punctuation stays with its sentence")
    func keepsClosingPunctuation() {
        let chunks = TextChunker.chunk(
            "The captain said \"stop right there.\" Then he turned and left.",
            maximumLength: 40
        )
        #expect(chunks.first == "The captain said \"stop right there.\"")
    }

    @Test("A stub sentence is merged forward rather than spoken alone")
    func mergesShortFragments() {
        // "Yes." on its own loses the prosodic run-on into what follows and
        // sounds clipped, so the chunker overruns the budget slightly instead.
        let chunks = TextChunker.chunk("Yes. The rest of this fits fine.", maximumLength: 30)
        #expect(chunks.first == "Yes. The rest of this fits fine.")
    }

    @Test(
        "A terminator glued to the next token is not a sentence end",
        arguments: [
            "Visit example.com for details.",
            "Open README.md in the editor.",
            "Upgrade to v1.2.3 today.",
            "The build takes 3.5 seconds.",
        ]
    )
    func gluedTerminatorsDoNotSplit(text: String) {
        #expect(TextChunker.chunk(text, maximumLength: 280) == [text])
    }

    @Test("Ellipses do not produce empty chunks")
    func ellipsesProduceNoEmptyChunks() {
        let chunks = TextChunker.chunk("Wait... what happened?", maximumLength: 10)
        #expect(chunks.allSatisfy { !$0.isEmpty })
        #expect(chunks.joined(separator: " ").contains("what happened?"))
    }

    @Test(
        "Abbreviations do not end a sentence",
        arguments: [
            "Dr. Chandra will see you now.",
            "Meet Mr. Smith at the office.",
            "Bring snacks, drinks, etc. to the party.",
            "See the guide, e.g. chapter four, for details.",
        ]
    )
    func abbreviationsDoNotSplit(text: String) {
        // Budget is generous, so any split here would be a false boundary.
        #expect(TextChunker.chunk(text, maximumLength: 280) == [text])
    }

    @Test("Decimal points do not end a sentence")
    func decimalsDoNotSplit() {
        let text = "The build takes 3.5 seconds on version 2.1 of the toolchain."
        #expect(TextChunker.chunk(text, maximumLength: 280) == [text])
    }

    @Test("Initials do not end a sentence")
    func initialsDoNotSplit() {
        let text = "J. R. R. Tolkien wrote it."
        #expect(TextChunker.chunk(text, maximumLength: 280) == [text])
    }

    // MARK: - Packing

    @Test("Short sentences pack together up to the budget")
    func packsShortSentences() {
        let chunks = TextChunker.chunk("One. Two. Three. Four.", maximumLength: 280)
        #expect(chunks == ["One. Two. Three. Four."])
    }

    @Test("Packing respects the budget")
    func respectsBudget() {
        let text = String(repeating: "The cat sat on the mat. ", count: 40)
        let chunks = TextChunker.chunk(text, maximumLength: 100)

        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= 100, "chunk overran the budget: \(chunk.count)")
        }
    }

    @Test("An over-long sentence is broken at clause punctuation")
    func hardSplitPrefersClauses() {
        let text =
            "This is a long sentence, which carries on past the budget, "
            + "and keeps going with yet another clause attached to it."
        let chunks = TextChunker.chunk(text, maximumLength: 60)

        #expect(chunks.count > 1)
        // The first seam should land on the comma, not mid-phrase.
        #expect(chunks[0].hasSuffix(","))
    }

    @Test("An over-long sentence with no punctuation splits on spaces")
    func hardSplitFallsBackToSpaces() {
        let text = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        let chunks = TextChunker.chunk(text, maximumLength: 50)

        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= 50)
        }
    }

    @Test("A single unbreakable token is emitted whole rather than sliced")
    func unbreakableTokenSurvives() {
        // Slicing a URL mid-token would make it unspeakable; better to overrun.
        let url = "https://example.com/" + String(repeating: "a", count: 200)
        let chunks = TextChunker.chunk(url, maximumLength: 50)
        #expect(chunks == [url])
    }

    // MARK: - Invariants

    @Test("No chunk is empty or whitespace-padded")
    func chunksAreClean() {
        let text = """
            First paragraph here.  It has two sentences.

            Second paragraph. And a third sentence!  Plus one more?
            """
        for chunk in TextChunker.chunk(text, maximumLength: 40) {
            #expect(!chunk.isEmpty)
            #expect(chunk == chunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @Test("Chunking preserves every word in order")
    func preservesContent() {
        let text = """
            Beagle runs entirely on device. It uses Parakeet for speech \
            recognition, and Kokoro for synthesis. Dr. Smith says 3.5 seconds \
            is fast enough for anyone!

            A second paragraph follows here.
            """

        let original = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let chunked = TextChunker.chunk(text, maximumLength: 60)
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }

        // The chunker must never drop, duplicate, or reorder words — only
        // decide where to breathe.
        #expect(chunked == original)
    }

    @Test("Chunking is stable across budgets", arguments: [20, 50, 120, 280, 1000])
    func preservesContentAtAnyBudget(budget: Int) {
        let text =
            "One sentence here. Another one follows, with a clause. "
            + "And a third; plus a fourth! Finally a fifth?"

        let original = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let chunked = TextChunker.chunk(text, maximumLength: budget)
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }

        #expect(chunked == original)
    }

    @Test(
        "Dotted abbreviations do not split even under a tight budget",
        arguments: [
            "See the guide, e.g. chapter four, for the details.",
            "The result, i.e. the transcript, appears at the cursor.",
        ]
    )
    func dottedAbbreviationsDoNotSplit(text: String) {
        // Regression: the abbreviation lookup used to keep internal periods, so
        // "e.g." reduced to "e.g" and matched nothing in the table. At a large
        // budget the packer silently rejoined the pieces and hid the bug; a
        // tight budget exposes the bad boundary.
        let chunks = TextChunker.chunk(text, maximumLength: 30)
        for chunk in chunks {
            #expect(chunk.hasSuffix("e.g.") == false, "split after e.g. in \(chunks)")
            #expect(chunk.hasSuffix("i.e.") == false, "split after i.e. in \(chunks)")
        }
    }
}
