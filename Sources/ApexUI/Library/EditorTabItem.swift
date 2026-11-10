import Foundation
import ApexCore

/// One open file in the editor pane. Commands and notes share the tab bar;
/// identity follows the file URL, which stays in sync across in-editor renames.
@MainActor
public final class EditorTabItem: ObservableObject, Identifiable {
    public let id = UUID()
    public let kind: LibraryFileKind

    @Published public var url: URL
    @Published public var group: String?
    @Published public var title: String
    @Published public var content: String
    @Published public var initialTitle: String
    @Published public var initialContent: String
    @Published public var isSaving = false
    @Published public var lastError: String?
    @Published public var savedNotice: String?

    public var isDirty: Bool { content != initialContent || title != initialTitle }

    public init(kind: LibraryFileKind, url: URL, title: String, group: String?, content: String) {
        self.kind = kind
        self.url = url
        self.group = group
        self.title = title
        self.content = content
        self.initialTitle = title
        self.initialContent = content
    }

    /// Persists dirty title/content through the library store (rename on title change,
    /// atomic content write). Safe to call repeatedly; no-ops when clean or saving.
    public func save(using library: LibraryStore) {
        guard isDirty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if title != initialTitle {
                let old = LibraryFile(url: url, kind: kind, title: initialTitle, group: group)
                let renamed = try library.rename(old, toTitle: title)
                url = renamed.url
                group = renamed.group
                title = renamed.title
            }
            let file = LibraryFile(url: url, kind: kind, title: title, group: group)
            try library.write(file, content: content)
            initialTitle = title
            initialContent = content
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            savedNotice = "已保存 \(formatter.string(from: Date()))"
        } catch {
            lastError = error.localizedDescription
        }
    }
}
