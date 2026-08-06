import Foundation

/// Splits prose into utterance-sized pieces for streaming synthesis.
///
/// Kokoro already chunks internally to respect its 510-phoneme input cap, so
/// this exists for a different reason: **perceived latency**. Synthesizing a
/// whole article before the first sample plays means several seconds of
/// silence. Splitting on sentence boundaries lets playback start after the
/// first sentence while the rest is still being generated, which turns a
/// multi-second wait into roughly 200 ms.
///
/// The splitter is deliberately conservative — a wrong split mid-sentence is
/// audible as a dropped beat, so ambiguous cases keep the text together.
public enum TextChunker {

    /// Target upper bound for one chunk, in characters.
    ///
    /// Chosen so a chunk stays comfortably inside Kokoro's phoneme cap (English
    /// runs well under one phoneme per character) while remaining short enough
    /// that the first chunk synthesizes fast.
    public static let defaultMaximumLength = 280

    /// Fragments shorter than this are glued onto the following chunk. Speaking
    /// "Yes." as its own utterance loses the prosodic run-on into the next
    /// sentence and sounds clipped.
    ///
    /// Kept small on purpose: this should rescue one- or two-word stubs, not
    /// merge ordinary short sentences, which would defeat the streaming split.
    private static let minimumChunkLength = 12

    /// Tokens that end in a period without ending a sentence.
    ///
    /// Not exhaustive by design: this list covers what actually shows up in
    /// English prose, and a miss costs one extra split, not a wrong word.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "mt",
        "vs", "etc", "eg", "ie", "cf", "al", "inc", "ltd", "co", "corp",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "approx", "dept", "est", "fig", "no", "vol", "pp", "ed",
    ]

    /// Split `text` into chunks no longer than `maximumLength` where possible.
    ///
    /// - Returns: Non-empty, whitespace-trimmed chunks in reading order. An
    ///   empty array when `text` holds nothing speakable.
    public static func chunk(
        _ text: String,
        maximumLength: Int = defaultMaximumLength
    ) -> [String] {
        precondition(maximumLength > 0, "maximumLength must be positive")

        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        let sentences = splitIntoSentences(normalized)
        return pack(sentences, maximumLength: maximumLength)
    }

    // MARK: - Normalization

    /// Collapse whitespace while preserving paragraph breaks as hard stops.
    ///
    /// Paragraph breaks become sentence terminators so a heading with no
    /// trailing period does not run into the paragraph beneath it.
    private static func normalize(_ text: String) -> String {
        var paragraphs: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            let collapsed =
                paragraph
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !collapsed.isEmpty { paragraphs.append(collapsed) }
        }
        return paragraphs.joined(separator: "\n")
    }

    // MARK: - Sentence segmentation

    private static let terminators: Set<Character> = [".", "!", "?", "…", "\n"]

    /// Break normalized text at sentence terminators.
    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            current.append(character)

            if terminators.contains(character) {
                // Absorb any run of closing punctuation ("...", "?!", `."`) so
                // it stays with the sentence it belongs to.
                var lookahead = index + 1
                while lookahead < characters.count,
                    terminators.contains(characters[lookahead])
                        || characters[lookahead] == "\"" || characters[lookahead] == "'"
                        || characters[lookahead] == ")" || characters[lookahead] == "]"
                {
                    current.append(characters[lookahead])
                    lookahead += 1
                }

                if isSentenceBoundary(
                    at: index,
                    followedBy: lookahead < characters.count ? characters[lookahead] : nil,
                    in: characters,
                    current: current
                ) {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { sentences.append(trimmed) }
                    current = ""
                }
                index = lookahead
                continue
            }
            index += 1
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty { sentences.append(trailing) }
        return sentences
    }

    /// Decide whether the terminator at `index` really ends a sentence.
    ///
    /// - Parameter next: The character after the terminator and any closing
    ///   punctuation, or `nil` at end of text.
    private static func isSentenceBoundary(
        at index: Int,
        followedBy next: Character?,
        in characters: [Character],
        current: String
    ) -> Bool {
        let character = characters[index]

        // Newlines are paragraph breaks; always a boundary.
        guard character != "\n" else { return true }

        // A terminator glued to the next token is punctuation inside a word, not
        // a full stop: "example.com", "README.md", "v1.2.3", "foo!bar". Real
        // sentence ends are always followed by whitespace or nothing at all.
        if let next, !next.isWhitespace { return false }

        guard character == "." else { return true }

        // A known abbreviation ("Dr.", "etc.") does not end the sentence.
        //
        // Internal periods are stripped as well as trailing ones, so dotted
        // forms reduce to the undotted spellings held in `abbreviations`:
        // "e.g." and "i.e." become "eg" and "ie" rather than "e.g" and "i.e",
        // which matched nothing and let the splitter cut the sentence in half.
        let lastWord =
            current
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:!?\"')]"))
            .replacingOccurrences(of: ".", with: "")
            .lowercased() ?? ""
        if abbreviations.contains(lastWord) { return false }

        // A single letter before the period is an initial ("J. R. R. Tolkien").
        if lastWord.count == 1, lastWord.first?.isLetter == true { return false }

        return true
    }

    // MARK: - Packing

    /// Combine sentences into chunks bounded by `maximumLength`.
    private static func pack(_ sentences: [String], maximumLength: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }

        for sentence in sentences {
            // A single sentence longer than the budget has to be broken up.
            guard sentence.count <= maximumLength else {
                flush()
                chunks.append(contentsOf: hardSplit(sentence, maximumLength: maximumLength))
                continue
            }

            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maximumLength {
                current += " " + sentence
            } else if current.count < minimumChunkLength {
                // Emitting a stub here would sound clipped; overrun the budget
                // slightly instead. Kokoro's own chunker handles the overflow.
                current += " " + sentence
                flush()
            } else {
                flush()
                current = sentence
            }
        }
        flush()

        return chunks
    }

    /// Split an over-long sentence, preferring clause punctuation over raw word
    /// boundaries so the seam lands somewhere a speaker would pause anyway.
    private static func hardSplit(_ sentence: String, maximumLength: Int) -> [String] {
        var pieces: [String] = []
        var remaining = Substring(sentence)

        while remaining.count > maximumLength {
            let window = remaining.prefix(maximumLength)

            // Clause punctuation only counts when whitespace follows it. Without
            // that check the colon in "https://example.com" reads as a clause
            // break and the URL gets sliced in half.
            let breakIndex =
                lastIndex(of: [",", ";", ":", "—", "–"], in: window, followedByWhitespaceIn: remaining)
                ?? lastIndex(of: [" "], in: window, followedByWhitespaceIn: nil)

            guard let breakIndex else {
                // A single unbroken token longer than the budget (a URL, say).
                // Emit it whole rather than slicing mid-word.
                break
            }

            let piece = remaining[..<remaining.index(after: breakIndex)]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            remaining = remaining[remaining.index(after: breakIndex)...]
        }

        let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    /// Index of the last character in `window` matching one of `targets`.
    ///
    /// - Parameter source: When non-`nil`, a match only counts if the character
    ///   after it in `source` is whitespace or end of text. Pass `nil` to accept
    ///   any match.
    private static func lastIndex(
        of targets: Set<Character>,
        in window: Substring,
        followedByWhitespaceIn source: Substring?
    ) -> Substring.Index? {
        var index = window.endIndex
        while index > window.startIndex {
            index = window.index(before: index)
            guard targets.contains(window[index]) else { continue }

            guard let source else { return index }
            let next = source.index(after: index)
            if next >= source.endIndex || source[next].isWhitespace { return index }
        }
        return nil
    }
}
