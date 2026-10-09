import SwiftUI

struct ClipRow: View {
    let item: ClipItem
    let order: Int?
    let highlighted: Bool
    @ObservedObject var store: ClipboardStore

    @State private var hovering = false

    private var selected: Bool { order != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SelectionBadge(order: order)

            VStack(alignment: .leading, spacing: 5) {
                content
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                actions
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(selected ? 0.45 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { store.tap(item.id) }
        .contextMenu {
            Button("Copy") { store.copy(item) }
            if item.kind == .text {
                Menu("Copy As") {
                    ForEach(TextTransform.allCases) { transform in
                        Button(transform.title) { store.copy(item, transform: transform) }
                    }
                }
            }
            Divider()
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item.id) }
            Button("Delete", role: .destructive) { store.delete(item.id) }
        }
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering }
        }
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }

    private var background: Color {
        if selected { return Color.accentColor.opacity(0.14) }
        if highlighted { return Color.primary.opacity(0.08) }
        if hovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(item.preview)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        case .image:
            if let image = store.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 72, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                Label("Image", systemImage: "photo")
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if let icon = store.appIcon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            if let name = item.sourceAppName {
                Text(name)
                Text("·")
            }
            Text(item.date.shortRelative)
            if let detail {
                Text("·")
                Text(detail)
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var detail: String? {
        switch item.kind {
        case .text:
            let count = item.text?.count ?? 0
            return count == 1 ? "1 char" : "\(count) chars"
        case .image:
            guard let image = store.thumbnail(for: item) else { return nil }
            return "\(Int(image.size.width))×\(Int(image.size.height))"
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            RowAction(icon: item.pinned ? "pin.slash.fill" : "pin.fill", help: item.pinned ? "Unpin" : "Pin") {
                store.togglePin(item.id)
            }
            RowAction(icon: "doc.on.doc.fill", help: "Copy Only This") {
                store.copy(item)
            }
            RowAction(icon: "trash.fill", help: "Delete", tint: .red) {
                store.delete(item.id)
            }
        }
    }
}

struct SelectionBadge: View {
    let order: Int?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(order == nil ? 0.45 : 0), lineWidth: 1.5)
            if let order {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .shadow(color: .accentColor.opacity(0.4), radius: 4, y: 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                Text("\(order)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
    }
}

struct RowAction: View {
    let icon: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? tint : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.1 : 0))
                )
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) { hovering = isHovering }
        }
    }
}
