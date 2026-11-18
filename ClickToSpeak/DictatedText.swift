import Foundation

enum DictationError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

/// SpeechTranscriber delivers successive hypotheses for its current phrase in order.
struct Transcript {
    private(set) var finalized = ""
    private(set) var provisional = ""
    private var finalizedThrough = -Double.infinity

    mutating func receive(_ words: String, end: Double, final: Bool) {
        guard end.isFinite, end > finalizedThrough else { return }
        provisional = words
        if final {
            finalized = text
            provisional = ""
            finalizedThrough = end
        }
    }

    var text: String {
        guard let last = finalized.last, let first = provisional.first else {
            return finalized + provisional
        }
        let needsSpace = (last.isLetter || last.isNumber) && (first.isLetter || first.isNumber)
        return finalized + (needsSpace ? " " : "") + provisional
    }
}

/// All offsets crossing the Accessibility boundary are UTF-16 offsets.
struct DictatedText {
    let prefix: String
    let suffix: String
    private(set) var expected: String
    private(set) var spoken = ""
    private(set) var selection: NSRange

    init(original: String, selection: NSRange) throws {
        guard Range(selection, in: original) != nil else {
            throw DictationError.message("La position du curseur est indisponible.")
        }
        let string = original as NSString
        let anchor = NSMaxRange(selection)
        prefix = string.substring(to: anchor)
        suffix = string.substring(from: anchor)
        expected = original
        self.selection = selection
    }

    func matches(_ value: String, _ range: NSRange) -> Bool {
        range == selection && value.utf16.elementsEqual(expected.utf16)
    }

    /// Keep the already-correct prefix, including any host rich-text attributes.
    func replacement(for next: String) -> (NSRange, String)? {
        if spoken.utf16.elementsEqual(next.utf16) { return nil }
        var old = spoken.startIndex
        var new = next.startIndex
        while old < spoken.endIndex, new < next.endIndex,
              spoken[old].utf8.elementsEqual(next[new].utf8) {
            old = spoken.index(after: old)
            new = next.index(after: new)
        }
        let common = spoken[..<old].utf16.count
        return (NSRange(location: prefix.utf16.count + common,
                        length: spoken.utf16.count - common), String(next[new...]))
    }

    mutating func accept(_ next: String) {
        spoken = next
        expected = prefix + next + suffix
        selection = NSRange(location: prefix.utf16.count + spoken.utf16.count, length: 0)
    }
}
