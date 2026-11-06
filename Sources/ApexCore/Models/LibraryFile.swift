import Foundation

/// Kind of file-backed library entry: a quick command (`.sh`) or a Markdown note (`.md`)
public enum LibraryFileKind: String, Sendable, Hashable {
    case command
    case note

    /// Subdirectory name directly under the library workdir
    public var directoryName: String {
        switch self {
        case .command: return "commands"
        case .note: return "notes"
        }
    }

    public var fileExtension: String {
        switch self {
        case .command: return "sh"
        case .note: return "md"
        }
    }
}

/// A single library file on disk. The filename (without extension) is the display
/// title and the containing subdirectory is the group, so a synced workdir stays
/// fully browsable and editable from Finder or any other machine.
public struct LibraryFile: Identifiable, Sendable, Equatable, Hashable {
    public let url: URL
    public let kind: LibraryFileKind
    /// Filename without extension
    public let title: String
    /// Group (= subdirectory name) or nil for top-level entries
    public let group: String?

    public init(url: URL, kind: LibraryFileKind, title: String, group: String?) {
        self.url = url
        self.kind = kind
        self.title = title
        self.group = group
    }

    public var id: URL { url }
}
