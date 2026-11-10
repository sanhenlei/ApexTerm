import SwiftUI
import MarkdownUI
import ApexCore

/// Editor for a Markdown note with three display modes: source, split, preview.
struct NoteFileEditorView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case edit
        case split
        case preview

        var id: String { rawValue }
    }

    @ObservedObject var tab: EditorTabItem
    let onSave: () -> Void
    let onClose: () -> Void

    @ObservedObject private var themeSettings = AppSettings.shared
    @State private var mode: DisplayMode = .split

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ApexStyle.s2) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundColor(ApexStyle.secondary)

                TextField("标题", text: $tab.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .semibold))
                    .help("标题即文件名，保存时重命名文件")

                if tab.isSaving {
                    ProgressView()
                        .controlSize(.mini)
                } else if tab.isDirty {
                    Circle()
                        .fill(ApexStyle.warning)
                        .frame(width: 6, height: 6)
                        .help("有未保存的修改")
                }

                if let notice = tab.savedNotice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundColor(ApexStyle.secondary)
                        .lineLimit(1)
                }
                if let error = tab.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(ApexStyle.error)
                        .lineLimit(1)
                        .help(error)
                }

                Spacer(minLength: ApexStyle.s1)

                Picker("显示模式", selection: $mode) {
                    Label("编辑", systemImage: "square.and.pencil").tag(DisplayMode.edit)
                    Label("分栏", systemImage: "rectangle.split.2x1").tag(DisplayMode.split)
                    Label("预览", systemImage: "eye").tag(DisplayMode.preview)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                ApexIconButton(
                    icon: "externaldrive",
                    label: "保存 (⌘S)",
                    size: 24,
                    iconSize: 11,
                    isSelected: true
                ) {
                    onSave()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!tab.isDirty)

                ApexIconButton(
                    icon: "xmark",
                    label: "关闭",
                    size: 24,
                    iconSize: 10
                ) {
                    onClose()
                }
                .help("关闭编辑窗口")
            }
            .padding(.horizontal, ApexStyle.s3)
            .padding(.vertical, ApexStyle.s2)

            Divider()

            switch mode {
            case .edit:
                editor
            case .preview:
                MarkdownPreviewView(markdown: tab.content)
            case .split:
                HStack(spacing: 0) {
                    editor
                    Divider()
                    MarkdownPreviewView(markdown: tab.content)
                }
            }

            Divider()

            HStack(spacing: ApexStyle.s2) {
                Text("\(tab.content.count) 字符")
                    .font(.caption2)
                    .foregroundColor(ApexStyle.secondary)
                Spacer()
                Text(tab.group ?? "未分组")
                    .font(.caption2)
                    .foregroundColor(ApexStyle.secondary)
            }
            .padding(.horizontal, ApexStyle.s3)
            .padding(.vertical, ApexStyle.s1)
        }
        .onChange(of: tab.content) { _, _ in
            tab.savedNotice = nil
            tab.lastError = nil
        }
        .onChange(of: tab.title) { _, _ in
            tab.lastError = nil
        }
    }

    /// Pure-SwiftUI source editor: NSViewRepresentable content does not paint inside
    /// sheets on current macOS, so the popup uses TextEditor instead.
    private var editor: some View {
        TextEditor(text: $tab.content)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(ApexStyle.primary)
            .scrollContentBackground(.hidden)
            .background(ApexStyle.surface)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// MarkdownUI wrapper rendering note content; falls back to the library's basic theme.
struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Markdown(markdown)
                .markdownTextStyle(\.code) {
                    FontFamilyVariant(.monospaced)
                }
                .padding(ApexStyle.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
