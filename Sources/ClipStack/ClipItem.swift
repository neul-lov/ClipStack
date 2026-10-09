import AppKit

struct ClipItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    var kind: Kind
    var text: String?
    var imageData: Data?
    var date: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    var pinned: Bool

    init(text: String, source: NSRunningApplication?) {
        id = UUID()
        kind = .text
        self.text = text
        imageData = nil
        date = Date()
        sourceBundleID = source?.bundleIdentifier
        sourceAppName = source?.localizedName
        pinned = false
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

    /// Single-line-friendly preview: trims surrounding whitespace and collapses long runs of blank lines.
    var preview: String {
        guard let text else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.prefix(4).joined(separator: "\n")
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
