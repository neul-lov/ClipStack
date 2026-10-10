import AppKit

struct ClipItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    var kind: Kind
    var text: String? {
        didSet { updateDerived() }
    }
    var imageData: Data?
    var date: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    var pinned: Bool

    // Worked out once per clip so rows don't rescan long text on every render. Not stored on disk.
    /// Up to four non-empty lines from the start of the text.
    private(set) var preview = ""
    /// Characters, including spaces and line breaks.
    private(set) var charCount = 0
    /// Characters without line breaks at either end, which is how clips are joined.
    private(set) var joinedCharCount = 0

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageData, date, sourceBundleID, sourceAppName, pinned
    }

    init(text: String, source: NSRunningApplication?) {
        id = UUID()
        kind = .text
        self.text = text
        imageData = nil
        date = Date()
        sourceBundleID = source?.bundleIdentifier
        sourceAppName = source?.localizedName
        pinned = false
        updateDerived()
    }

    init(imageData: Data, source: NSRunningApplication?) {
        id = UUID()
        kind = .image
        text = nil
        self.imageData = imageData
        date = Date()
        sourceBundleID = source?.bundleIdentifier
        sourceAppName = source?.localizedName
        pinned = false
    }

    /// Only the content is required; every other field falls back to a default, so history written
    /// by an older or newer version still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        imageData = try? container.decodeIfPresent(Data.self, forKey: .imageData)
        guard text != nil || imageData != nil else {
            throw DecodingError.dataCorruptedError(forKey: .text, in: container, debugDescription: "Clip has no content")
        }
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? (text != nil ? .text : .image)
        date = (try? container.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        sourceBundleID = try? container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try? container.decodeIfPresent(String.self, forKey: .sourceAppName)
        pinned = (try? container.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        updateDerived()
    }

    private mutating func updateDerived() {
        guard let text else {
            preview = ""
            charCount = 0
            joinedCharCount = 0
            return
        }
        preview = text.prefix(4000)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "\n")
        charCount = text.count
        joinedCharCount = text.trimmingCharacters(in: .newlines).count
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if let text, text.localizedCaseInsensitiveContains(query) { return true }
        if let sourceAppName, sourceAppName.localizedCaseInsensitiveContains(query) { return true }
        if kind == .image, "image".localizedCaseInsensitiveContains(query) { return true }
        return false
    }
}

enum JoinSeparator: String, CaseIterable, Identifiable, Codable {
    case nothing
    case newLine
    case blankLine
    case space
    case comma

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .newLine: "New Line"
        case .blankLine: "Blank Line"
        case .space: "Space"
        case .comma: "Comma"
        }
    }

    var value: String {
        switch self {
        case .nothing: ""
        case .newLine: "\n"
        case .blankLine: "\n\n"
        case .space: " "
        case .comma: ", "
        }
    }
}

extension Date {
    var shortRelative: String {
        let seconds = Int(Date().timeIntervalSince(self))
        if seconds < 45 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

enum Retention: String, CaseIterable, Identifiable {
    case forever
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: "Forever"
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        }
    }

    /// Clips older than this are removed, unless pinned.
    var maxAge: TimeInterval? {
        switch self {
        case .forever: nil
        case .day: 60 * 60 * 24
        case .week: 60 * 60 * 24 * 7
        case .month: 60 * 60 * 24 * 30
        }
    }
}

enum TextTransform: String, CaseIterable, Identifiable {
    case trimSpaces
    case singleLine
    case uppercase
    case lowercase
    case titleCase
    case removeQuotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trimSpaces: "Trim Spaces"
        case .singleLine: "Single Line"
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .titleCase: "Title Case"
        case .removeQuotes: "Remove Quotes"
        }
    }

    var icon: String {
        switch self {
        case .trimSpaces: "scissors"
        case .singleLine: "arrow.right.to.line"
        case .uppercase: "textformat.size.larger"
        case .lowercase: "textformat.size.smaller"
        case .titleCase: "textformat"
        case .removeQuotes: "quote.opening"
        }
    }

    private static let word = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}'’]+")

    func apply(to text: String) -> String {
        switch self {
        case .trimSpaces:
            // Trim each line and squeeze runs of spaces or tabs into one space.
            return text.components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .singleLine:
            return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            // Capitalize words that are all lowercase; words like iPhone, macOS or NASA stay as they are.
            var result = text
            let matches = Self.word.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let word = result[range]
                guard !word.contains(where: \.isUppercase),
                      let first = word.firstIndex(where: \.isLetter) else { continue }
                result.replaceSubrange(first...first, with: word[first].uppercased())
            }
            return result
        case .removeQuotes:
            // Quote marks around text go; apostrophes inside words (don't, it's) stay.
            return text
                .replacingOccurrences(of: "[\"`“”«»„]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "(?<![\\p{L}\\p{N}])['‘’]|['‘’](?![\\p{L}\\p{N}])", with: "",
                                      options: .regularExpression)
        }
    }
}
