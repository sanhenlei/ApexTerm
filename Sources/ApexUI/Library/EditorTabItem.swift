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
}
