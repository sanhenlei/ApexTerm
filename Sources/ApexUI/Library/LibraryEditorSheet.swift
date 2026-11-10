import SwiftUI
import ApexCore

/// Popup editor window for a library file (quick command or Markdown note).
/// Replaces the former right-side editor pane: opening a file never touches the
/// workspace layout, so terminal/editor rendering cannot interfere with it.
public struct LibraryEditorSheet: View {
    @ObservedObject public var item: EditorTabItem
    public let onInsertCommand: (_ command: String, _ executeNow: Bool) -> Void
    public let onClose: () -> Void
    @State private var pendingClose = false

    public init(item: EditorTabItem, onInsertCommand: @escaping (_ command: String, _ executeNow: Bool) -> Void, onClose: @escaping () -> Void) {
        self.item = item
        self.onInsertCommand = onInsertCommand
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            switch item.kind {
            case .command:
                CommandFileEditorView(
                    tab: item,
                    onSave: { item.save(using: LibraryStore.shared) },
                    onClose: { requestClose() },
                    onInsertCommand: onInsertCommand
                )
            case .note:
                NoteFileEditorView(
                    tab: item,
                    onSave: { item.save(using: LibraryStore.shared) },
                    onClose: { requestClose() }
                )
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .interactiveDismissDisabled(item.isDirty)
        .confirmationDialog("有未保存的修改", isPresented: $pendingClose) {
            Button("放弃更改并关闭", role: .destructive) { onClose() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("「\(item.title)」尚未保存的更改将丢失。")
        }
    }

    private func requestClose() {
        if item.isDirty {
            pendingClose = true
        } else {
            onClose()
        }
    }
}
