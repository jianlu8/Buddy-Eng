import Foundation

typealias SpeechChunker = ConversationOrchestrator.SpeechChunker

enum SpokenTextSuppressionCategory: String, Hashable, Sendable {
    case markdownControl
    case emoji
    case links
    case code
    case listMarker
    case speakerLabel
    case stageDirection
    case decorativePunctuation
    case filePath
}

struct SpeechMarkupState: Equatable, Sendable {
    var hasOpenEmphasis = false
    var hasOpenInlineCode = false
    var hasOpenFencedCodeBlock = false
    var hasPendingMarkdownLink = false
    var hasPendingStageDirection = false

    var hasDeferredMarkup: Bool {
        hasOpenEmphasis
            || hasOpenInlineCode
            || hasOpenFencedCodeBlock
            || hasPendingMarkdownLink
            || hasPendingStageDirection
    }
}

struct SpokenTextNormalizationResult: Equatable, Sendable {
    let spokenText: String
    let hasSpeakableContent: Bool
    let hasDeferredMarkup: Bool
    let suppressedCategories: Set<SpokenTextSuppressionCategory>
}

struct SpokenTextNormalizer {
    private(set) var markupState = SpeechMarkupState()

    mutating func reset() {
        markupState = SpeechMarkupState()
    }

    mutating func normalizeStreamingBuffer(
        _ rawBuffer: inout String,
        finalize: Bool = false
    ) -> SpokenTextNormalizationResult {
        let stableText: String
        if finalize {
            stableText = rawBuffer
            rawBuffer = ""
            markupState = SpeechMarkupState()
        } else {
            let scan = Self.deferredScan(in: rawBuffer)
            markupState = scan.state
            if let boundary = scan.boundary {
                stableText = String(rawBuffer[..<boundary])
                rawBuffer = String(rawBuffer[boundary...])
            } else {
                stableText = rawBuffer
                rawBuffer = ""
            }
        }

        var suppressedCategories = Set<SpokenTextSuppressionCategory>()
        let spokenText = Self.normalizeStableText(
            stableText,
            suppressedCategories: &suppressedCategories
        )

        return SpokenTextNormalizationResult(
            spokenText: spokenText,
            hasSpeakableContent: Self.containsSpeakableContent(spokenText),
            hasDeferredMarkup: markupState.hasDeferredMarkup,
            suppressedCategories: suppressedCategories
        )
    }

    private static func normalizeStableText(
        _ text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        guard text.isEmpty == false else { return "" }

        var working = text.replacingOccurrences(of: "\r\n", with: "\n")
        working = replaceMarkdownLinks(in: working, suppressedCategories: &suppressedCategories)
        working = removeCodeSegments(in: working, suppressedCategories: &suppressedCategories)
        working = removeSpeakerLabels(in: working, suppressedCategories: &suppressedCategories)
        working = replaceOrderedListMarkers(in: working, suppressedCategories: &suppressedCategories)
        working = removeLineFormatting(in: working, suppressedCategories: &suppressedCategories)
        working = removeStageDirections(in: working, suppressedCategories: &suppressedCategories)
        working = removeBareURLsAndPaths(in: working, suppressedCategories: &suppressedCategories)
        working = stripMarkdownControlCharacters(in: working, suppressedCategories: &suppressedCategories)
        working = removeEmojiCharacters(in: working, suppressedCategories: &suppressedCategories)
        working = normalizeDecorativePunctuation(in: working, suppressedCategories: &suppressedCategories)
        working = normalizeWhitespace(in: working)
        return working
    }

    private static func deferredScan(in text: String) -> (boundary: String.Index?, state: SpeechMarkupState) {
        let characters = Array(text)
        var openFence: Int?
        var openInlineCode: Int?
        var openLinkLabel: Int?
        var openLinkDestination: Int?
        var openEmphasis: (marker: Character, index: Int)?
        var openStageDirection: Int?
        var index = 0

        while index < characters.count {
            if hasPrefix("```", characters: characters, at: index) {
                if openFence == nil {
                    openFence = index
                } else {
                    openFence = nil
                }
                index += 3
                continue
            }

            if openFence != nil {
                index += 1
                continue
            }

            let character = characters[index]

            if character == "`" {
                if openInlineCode == nil {
                    openInlineCode = index
                } else {
                    openInlineCode = nil
                }
                index += 1
                continue
            }

            if openInlineCode != nil {
                index += 1
                continue
            }

            if openLinkDestination != nil {
                if character == ")" {
                    openLinkDestination = nil
                }
                index += 1
                continue
            }

            if openLinkLabel != nil {
                if character == "]" {
                    if index + 1 < characters.count, characters[index + 1] == "(" {
                        openLinkDestination = openLinkLabel
                        openLinkLabel = nil
                        index += 2
                        continue
                    }
                    openLinkLabel = nil
                }
                index += 1
                continue
            }

            if character == "[" {
                openLinkLabel = index
                index += 1
                continue
            }

            if openStageDirection != nil {
                if character == ")" {
                    openStageDirection = nil
                }
                index += 1
                continue
            }

            if character == "(", isLikelyStageDirectionStart(characters: characters, at: index) {
                openStageDirection = index
                index += 1
                continue
            }

            if isPotentialEmphasisMarker(characters: characters, at: index) {
                if let currentEmphasis = openEmphasis, currentEmphasis.marker == character {
                    openEmphasis = nil
                } else {
                    openEmphasis = (marker: character, index: index)
                }
            }

            index += 1
        }

        let state = SpeechMarkupState(
            hasOpenEmphasis: openEmphasis != nil,
            hasOpenInlineCode: openInlineCode != nil,
            hasOpenFencedCodeBlock: openFence != nil,
            hasPendingMarkdownLink: openLinkLabel != nil || openLinkDestination != nil,
            hasPendingStageDirection: openStageDirection != nil
        )
        let boundaryOffset = [
            openFence,
            openInlineCode,
            openLinkLabel,
            openLinkDestination,
            openEmphasis?.index,
            openStageDirection
        ]
        .compactMap { $0 }
        .min()

        if let boundaryOffset {
            return (text.index(text.startIndex, offsetBy: boundaryOffset), state)
        }
        return (nil, state)
    }

    private static func replaceMarkdownLinks(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0

        while index < characters.count {
            guard characters[index] == "[",
                  let closeBracket = firstIndex(of: "]", in: characters, from: index + 1),
                  closeBracket + 1 < characters.count,
                  characters[closeBracket + 1] == "(",
                  let closeParen = firstBalancedClosingParen(in: characters, from: closeBracket + 2)
            else {
                output.append(characters[index])
                index += 1
                continue
            }

            suppressedCategories.insert(.links)
            output += String(characters[(index + 1)..<closeBracket])
            index = closeParen + 1
        }

        return output
    }

    private static func removeCodeSegments(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0

        while index < characters.count {
            if hasPrefix("```", characters: characters, at: index),
               let closeFence = firstPrefixIndex("```", in: characters, from: index + 3) {
                suppressedCategories.insert(.code)
                index = closeFence + 3
                continue
            }

            if characters[index] == "`",
               let closeTick = firstIndex(of: "`", in: characters, from: index + 1) {
                suppressedCategories.insert(.code)
                index = closeTick + 1
                continue
            }

            output.append(characters[index])
            index += 1
        }

        return output
    }

    private static func removeSpeakerLabels(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        let cleaned = text.replacingMatches(
            of: #"(?im)^\s*(assistant|user|system|tutor|coach|annie)\s*:\s*"#
        ) { _, _ in
            suppressedCategories.insert(.speakerLabel)
            return ""
        }
        return cleaned
    }

    private static func replaceOrderedListMarkers(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        var working = text.replacingMatches(
            of: #"(?<!\w)([1-9][0-9]*)\.\s+"#
        ) { match, source in
            let number = Int(source.substring(with: match.range(at: 1))) ?? 0
            suppressedCategories.insert(.listMarker)
            return ordinalConnector(for: number) + " "
        }

        working = working.replacingMatches(
            of: #"\b(First,|Second,|Third,|Next,)\s+([A-Z])([a-z]+)"#
        ) { match, source in
            let connector = source.substring(with: match.range(at: 1))
            let firstLetter = source.substring(with: match.range(at: 2)).lowercased()
            let remainder = source.substring(with: match.range(at: 3))
            return "\(connector) \(firstLetter)\(remainder)"
        }
        return working
    }

    private static func removeLineFormatting(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        var working = text.replacingMatches(of: #"(?m)^\s*#{1,6}\s+"#) { _, _ in
            suppressedCategories.insert(.markdownControl)
            return ""
        }
        working = working.replacingMatches(of: #"(?m)^\s*>\s+"#) { _, _ in
            suppressedCategories.insert(.markdownControl)
            return ""
        }
        working = working.replacingMatches(of: #"(?m)^\s*[-•*]\s+"#) { _, _ in
            suppressedCategories.insert(.listMarker)
            return ""
        }
        return working
    }

    private static func removeStageDirections(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "(",
               let closeParen = firstIndex(of: ")", in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<closeParen])
                if isLikelyStageDirectionContent(content) {
                    suppressedCategories.insert(.stageDirection)
                    index = closeParen + 1
                    continue
                }
            }

            if character == "[",
               let closeBracket = firstIndex(of: "]", in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<closeBracket])
                if isLikelyStageDirectionContent(content) {
                    suppressedCategories.insert(.stageDirection)
                    index = closeBracket + 1
                    continue
                }
            }

            output.append(character)
            index += 1
        }

        return output
    }

    private static func removeBareURLsAndPaths(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        var working = text.replacingMatches(
            of: #"(^|\s)(https?://\S+|www\.\S+)"#
        ) { match, source in
            suppressedCategories.insert(.links)
            let leadingWhitespace = source.substring(with: match.range(at: 1))
            return leadingWhitespace
        }
        working = working.replacingMatches(
            of: #"(^|\s)(/[A-Za-z0-9._/\-]+|[A-Za-z]:\\[^\s]+)"#
        ) { match, source in
            suppressedCategories.insert(.filePath)
            let leadingWhitespace = source.substring(with: match.range(at: 1))
            return leadingWhitespace
        }
        return working
    }

    private static func stripMarkdownControlCharacters(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        let stripped = text.filter { character in
            let shouldSuppress = "*_~#>".contains(character)
            if shouldSuppress {
                suppressedCategories.insert(.markdownControl)
            }
            return shouldSuppress == false
        }
        return stripped
    }

    private static func removeEmojiCharacters(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        let filtered = text.filter { character in
            let shouldSuppress = isEmojiCharacter(character)
            if shouldSuppress {
                suppressedCategories.insert(.emoji)
            }
            return shouldSuppress == false
        }
        return filtered
    }

    private static func normalizeDecorativePunctuation(
        in text: String,
        suppressedCategories: inout Set<SpokenTextSuppressionCategory>
    ) -> String {
        var working = text.replacingMatches(of: #"[—–-]{2,}"#) { _, _ in
            suppressedCategories.insert(.decorativePunctuation)
            return ", "
        }
        working = working.replacingMatches(of: #"\.{2,}"#) { _, _ in
            suppressedCategories.insert(.decorativePunctuation)
            return "."
        }
        working = working.replacingMatches(of: #"!{2,}"#) { _, _ in
            suppressedCategories.insert(.decorativePunctuation)
            return "!"
        }
        working = working.replacingMatches(of: #"\?{2,}"#) { _, _ in
            suppressedCategories.insert(.decorativePunctuation)
            return "?"
        }
        return working
    }

    private static func normalizeWhitespace(in text: String) -> String {
        var working = text.replacingMatches(of: #"\s+"#) { _, _ in " " }
        working = working.replacingMatches(of: #"\s+([,.;:!?])"#) { match, source in
            source.substring(with: match.range(at: 1))
        }
        working = working.replacingMatches(of: #"([,.;:!?])([A-Za-z])"#) { match, source in
            let punctuation = source.substring(with: match.range(at: 1))
            let nextCharacter = source.substring(with: match.range(at: 2))
            return "\(punctuation) \(nextCharacter)"
        }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ordinalConnector(for number: Int) -> String {
        switch number {
        case 1:
            return "First,"
        case 2:
            return "Second,"
        case 3:
            return "Third,"
        default:
            return "Next,"
        }
    }

    private static func containsSpeakableContent(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
    }

    private static func isEmojiCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.isASCII == false)
        }
    }

    private static func isPotentialEmphasisMarker(characters: [Character], at index: Int) -> Bool {
        let character = characters[index]
        guard character == "*" || character == "_" || character == "~" else { return false }
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        let canOpen = next.map { $0.isWhitespace == false } ?? false
        let canClose = previous.map { $0.isWhitespace == false } ?? false
        return canOpen || canClose
    }

    private static func isLikelyStageDirectionStart(characters: [Character], at index: Int) -> Bool {
        guard index + 1 < characters.count else { return false }
        let nextCharacter = characters[index + 1]
        guard nextCharacter.isLetter else { return false }
        guard nextCharacter.isUppercase == false else { return false }
        if index == 0 {
            return true
        }
        let previousCharacter = characters[index - 1]
        return previousCharacter.isWhitespace || ".!?".contains(previousCharacter)
    }

    private static func isLikelyStageDirectionContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.count <= 40 else { return false }
        guard trimmed.rangeOfCharacter(from: CharacterSet.decimalDigits) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?/:")) == nil else { return false }
        guard trimmed == trimmed.lowercased() else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.whitespaces.contains(scalar)
                || scalar == "-"
                || scalar == "'"
                || scalar == ","
        }
    }

    private static func hasPrefix(_ prefix: String, characters: [Character], at index: Int) -> Bool {
        let prefixCharacters = Array(prefix)
        guard index + prefixCharacters.count <= characters.count else { return false }
        return Array(characters[index..<(index + prefixCharacters.count)]) == prefixCharacters
    }

    private static func firstPrefixIndex(_ prefix: String, in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count else { return nil }
        for index in start..<characters.count {
            if hasPrefix(prefix, characters: characters, at: index) {
                return index
            }
        }
        return nil
    }

    private static func firstIndex(of character: Character, in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count else { return nil }
        for index in start..<characters.count where characters[index] == character {
            return index
        }
        return nil
    }

    private static func firstBalancedClosingParen(in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count else { return nil }
        var depth = 1
        for index in start..<characters.count {
            if characters[index] == "(" {
                depth += 1
            } else if characters[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }
}

private extension String {
    func replacingMatches(
        of pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        replacingMatches(of: pattern, options: options) { match, source in
            source.substring(with: match.range)
        }
    }

    func replacingMatches(
        of pattern: String,
        options: NSRegularExpression.Options = [],
        _ transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return self
        }

        let source = self as NSString
        let matches = expression.matches(
            in: self,
            range: NSRange(location: 0, length: source.length)
        )
        guard matches.isEmpty == false else { return self }

        var output = ""
        var currentLocation = 0
        for match in matches {
            let prefixRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            output += source.substring(with: prefixRange)
            output += transform(match, source)
            currentLocation = match.range.location + match.range.length
        }
        output += source.substring(from: currentLocation)
        return output
    }
}
