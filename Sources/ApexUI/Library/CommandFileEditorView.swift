import SwiftUI
import ApexCore

/// Editor for a quick-command file: title field (renames the file on save) plus a
/// monospaced command editor. Insert types into the terminal without executing;
/// Run types and presses Enter.
struct CommandFileEditorView: View {
    @ObservedObject var tab: EditorTabItem
    let onSave: () -> Void
    let onClose: () -> Void
    let onInsertCommand: (_ command: String, _ executeNow: Bool) -> Void

    @ObservedObject private var themeSettings = AppSettings.shared

    private var lineCount: Int {
        tab.content.isEmpty ? 0 : tab.content.components(separatedBy: .newlines).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ApexStyle.s2) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(ApexStyle.accent)

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

                ApexActionButton(
                    "插入",
                    icon: "terminal",
                    tint: ApexStyle.secondary,
                    size: .small
                ) {
                    onInsertCommand(tab.content, false)
                }
                .disabled(tab.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                ApexActionButton(
                    "执行",
                    icon: "play.fill",
                    tint: ApexStyle.accent,
                    size: .small
                ) {
                    onInsertCommand(tab.content, true)
                }
                .disabled(tab.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

            LineNumberedTextEditor(text: $tab.content, fontSize: 13)
                .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: ApexStyle.s2) {
                Text("\(tab.content.count) 字符 · \(lineCount) 行")
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

/// Pure-SwiftUI line-numbered code editor for sheets. NSViewRepresentable content
/// does not paint inside sheets on current macOS, so the editor itself stays the
/// stock TextEditor; the gutter is driven by an off-screen NSLayoutManager that
/// measures the exact wrapped layout with the same font, width and fragment
/// padding as TextEditor's internals (pure computation, nothing enters the view
/// tree). The TextEditor is sized to its full content so it never scrolls
/// internally, and gutter + editor live in one outer ScrollView that scrolls
/// them together — numbers stay aligned with wrapped and scrolled text alike.
struct LineNumberedTextEditor: View {
    @Binding var text: String
    let fontSize: CGFloat

    /// Vertical inset SwiftUI's TextEditor applies to its text container.
    /// Calibrated against screenshots on current macOS: the inset is effectively
    /// zero, so the gutter needs no compensation.
    private let textTopInset: CGFloat = 0
    private let fragmentPadding: CGFloat = 5 // NSTextView default lineFragmentPadding

    private struct GutterRow: Identifiable {
        let id: Int
        let label: String
    }

    private struct MeasuredLayout {
        var rows: [GutterRow]
        var rowHeight: CGFloat
        var totalHeight: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            let digits = max(2, "\(lineDigits)".count)
            let gutterWidth = CGFloat(digits) * fontSize * 0.6 + 10
            let editorWidth = max(60, geo.size.width - gutterWidth - ApexStyle.s2)
            let layout = Self.measure(
                text: text,
                font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                width: editorWidth,
                fragmentPadding: fragmentPadding
            )
            let editorHeight = max(geo.size.height, layout.totalHeight + 2 * textTopInset + layout.rowHeight)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: ApexStyle.s2) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(layout.rows) { row in
                            Text(row.label)
                                .font(.system(size: fontSize - 1, design: .monospaced))
                                .foregroundColor(ApexStyle.secondary.opacity(0.7))
                                .frame(width: gutterWidth, height: layout.rowHeight, alignment: .center)
                        }
                    }
                    .padding(.top, textTopInset)

                    TextEditor(text: $text)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundColor(ApexStyle.primary)
                        .scrollContentBackground(.hidden)
                        .background(ApexStyle.surface)
                        .frame(width: editorWidth, height: editorHeight)
                        .padding(.bottom, 0)
                }
            }
            .background(ApexStyle.surface)
        }
    }

    private var lineDigits: Int { text.components(separatedBy: .newlines).count }

    /// Lays the text out off-screen with NSLayoutManager and returns one gutter
    /// entry per visual row: the logical line number on a row that starts a new
    /// line, empty on wrapped continuation rows.
    private static func measure(text: String, font: NSFont, width: CGFloat, fragmentPadding: CGFloat) -> MeasuredLayout {
        // Placeholder glyph keeps a single row for empty content.
        let storage = NSTextStorage(attributedString: NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font]))
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: width - 2 * fragmentPadding, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = fragmentPadding
        layoutManager.addTextContainer(container)

        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.ensureLayout(for: container)

        // Logical line start offsets in UTF-16 space (layout manager indexing).
        let nsText = text as NSString
        var lineStarts: [Int] = [0]
        var searchFrom = 0
        while searchFrom < nsText.length {
            let range = nsText.rangeOfCharacter(from: .newlines, options: [], range: NSRange(location: searchFrom, length: nsText.length - searchFrom))
            guard range.location != NSNotFound else { break }
            let next = range.location + range.length
            lineStarts.append(next)
            searchFrom = next
        }

        var rows: [GutterRow] = []
        var nextLineIndex = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, fragGlyphRange, _ in
            let charIndex = layoutManager.characterRange(forGlyphRange: fragGlyphRange, actualGlyphRange: nil).location
            if nextLineIndex < lineStarts.count, charIndex >= lineStarts[nextLineIndex] {
                rows.append(GutterRow(id: rows.count, label: "\(nextLineIndex + 1)"))
                nextLineIndex += 1
                // Swallow empty logical lines that produced no glyphs of their own.
                while nextLineIndex < lineStarts.count, lineStarts[nextLineIndex] <= charIndex {
                    nextLineIndex += 1
                }
            } else {
                rows.append(GutterRow(id: rows.count, label: ""))
            }
        }

        let used = layoutManager.usedRect(for: container)
        let rowHeight = rows.isEmpty ? layoutManager.defaultLineHeight(for: font) : used.height / CGFloat(rows.count)
        return MeasuredLayout(rows: rows, rowHeight: rowHeight, totalHeight: max(used.height, rowHeight))
    }
}
}
