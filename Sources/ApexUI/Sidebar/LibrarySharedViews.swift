import SwiftUI
import AppKit
import ApexCore

/// Shared row for library files: title only, content stays hidden until opened.
/// Clicking the row runs `onPrimary` (commands type into the terminal, notes open the editor);
/// the hover pencil always opens the editor.
struct LibraryFileRow: View {
    let file: LibraryFile
    let icon: String
    let iconColor: Color
    let primaryActionLabel: String
    let showsExecuteHint: Bool
    let onPrimary: (_ executeNow: Bool) -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onPrimary(NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: ApexStyle.s2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 14)

                Text(file.title)
                    .font(.subheadline)
                    .foregroundColor(ApexStyle.primary)
                    .lineLimit(1)

                Spacer(minLength: ApexStyle.s1)

                ApexIconButton(
                    icon: "pencil",
                    label: "编辑 \(file.title)",
                    size: 22,
                    iconSize: 10,
                    tint: isHovered ? ApexStyle.accent : nil
                ) {
                    onOpen()
                }
                .opacity(isHovered ? 1.0 : 0.0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: ApexStyle.badgeRadius)
                    .fill(isHovered ? ApexStyle.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsExecuteHint ? "\(primaryActionLabel)（按住 ⌥ 立即执行）" : primaryActionLabel)
        .onHover { hovering in
            withAnimation(ApexStyle.hoverTransition) {
                isHovered = hovering
            }
        }
    }
}

/// Disclosure label for a library group (= workdir subdirectory) with rename/delete menu.
struct LibraryGroupLabel: View {
    let name: String
    let count: Int
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(ApexStyle.secondary)
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ApexStyle.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(ApexStyle.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: ApexStyle.badgeRadius))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("重命名分组") { onRename() }
            Divider()
            Button("删除分组", role: .destructive) { onDelete() }
        }
    }
}

/// Bottom toast mirroring the sessions sidebar feedback pattern.
struct LibraryToastOverlay: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ApexStyle.warning)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ApexStyle.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .apexGlassCard(cornerRadius: 14, material: .regularMaterial, borderColor: Color.primary.opacity(0.12), shadowRadius: 8)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

/// Empty state shown when the library workdir has not been configured yet.
struct LibraryWorkdirEmptyState: View {
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("尚未选择工作目录")
                    .font(.headline)
                    .foregroundColor(ApexStyle.primary)
                Text("快捷命令与笔记以文件形式保存在工作目录中，\n可放入 iCloud Drive 或其他同步盘实现多设备同步。")
                    .font(.subheadline)
                    .foregroundStyle(ApexStyle.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            ApexActionButton(
                "选择工作目录",
                icon: "folder",
                tint: ApexStyle.accent,
                size: .regular,
                isProminent: true
            ) {
                onChoose()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
