import SwiftUI
import AppKit
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

    @ObservedObject private var themeSettings = AppSettings.shared
    @State private var showsFindBar = false
    @State private var mode: DisplayMode = .split

    private var editorPalette: NativeCodeEditor.EditorPalette? {
        guard !themeSettings.followsSystemAppearance else { return nil }
        return NativeCodeEditor.EditorPalette(
            background: NSColor(ApexStyle.surface),
            text: NSColor(ApexStyle.primary),
            gutter: NSColor(ApexStyle.subtleSurface),
            gutterText: NSColor(ApexStyle.secondary),
            selection: NSColor(ApexStyle.selection)
        )
    }

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
                    Label("分栏", systemImage: "columns").tag(DisplayMode.split)
                    Label("预览", systemImage: "eye").tag(DisplayMode.preview)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                ApexIconButton(
                    icon: "square.and.arrow.down",
                    label: "保存 (⌘S)",
                    size: 24,
                    iconSize: 11,
                    isSelected: true
                ) {
                    onSave()
                }
                .disabled(!tab.isDirty)
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

    private var editor: some View {
        NativeCodeEditor(
            text: $tab.content,
            showsFindBar: $showsFindBar,
            isReloading: false,
            palette: editorPalette
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// MarkdownUI wrapper rendering note content with the workspace palette.
struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Markdown(markdown)
                .markdownTheme(.base)
                .markdownTextStyle(\.code) {
                    $0.font(.system(.body, design: .monospaced))
                }
                .padding(ApexStyle.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
