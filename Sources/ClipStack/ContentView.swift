import SwiftUI

struct ContentView: View {
    static let width: CGFloat = 380
    static let height: CGFloat = 540

    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool
    @State private var rowFrames: [UUID: CGRect] = [:]
    /// How far the list is scrolled, so pointer positions in the visible area map onto rows.
    @State private var scrollOffset: CGFloat = 0
    @State private var dragStart: CGPoint?
    @State private var pointerInViewport: CGFloat = 0
    @StateObject private var autoScroller = DragAutoScroller()

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            list
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .fontDesign(.rounded)
        .overlay(alignment: .bottom) { toast }
        .onChange(of: store.openToken) {
            searchFocused = true
        }
        .onAppear { searchFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("ClipStack")
                    .font(.system(size: 15, weight: .bold))
                if store.historySaved {
                    Text(store.items.isEmpty ? "Waiting for your first copy" : "\(store.items.count) clips")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else {
                    Text("Not saving: keychain access was denied")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { store.tapEmptySpace() }
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Join Multiple Items With", selection: $store.separator) {
                ForEach(JoinSeparator.allCases) { Text($0.title).tag($0) }
            }
            Picker("Keep History", selection: $store.retention) {
                ForEach(Retention.allCases) { Text($0.title).tag($0) }
            }
            Picker("Open Shortcut", selection: $store.shortcut) {
                ForEach(Shortcut.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Paste After Copying", isOn: $store.pasteAfterCopy)
            Toggle("Skip Passwords & Keys", isOn: $store.skipSecrets)
            Toggle("Launch at Login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            Divider()
            Button("Clear History (Keeps Pinned)") { store.clearHistory() }
            Divider()
            Button("Quit ClipStack") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search clips", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($searchFocused)
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.15), value: store.query.isEmpty)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let pinned = store.pinnedItems
        let recent = store.recentItems
        if pinned.isEmpty && recent.isEmpty {
            emptyState
        } else {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        listContent(pinned: pinned, recent: recent, viewport: geometry.size.height, proxy: proxy)
                    }
                    .coordinateSpace(name: "viewport")
                    .scrollIndicators(.never)
                    .onChange(of: store.highlightedID) { _, id in
                        guard let id, dragStart == nil else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
    }

    private func listContent(pinned: [ClipItem], recent: [ClipItem], viewport: CGFloat,
                             proxy: ScrollViewProxy) -> some View {
        // A plain VStack (not lazy) so every row has a frame, which drag selection needs. History is
        // capped at a few hundred clips with cached previews, so this stays cheap.
        VStack(spacing: 4) {
            if !pinned.isEmpty {
                sectionTitle("Pinned", icon: "pin.fill")
                ForEach(pinned) { row($0) }
                if !recent.isEmpty { sectionTitle("Recent", icon: "clock") }
            }
            ForEach(recent) { row($0) }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        // Fill the visible area so clicks and drags on the empty space below the clips land here.
        .frame(maxWidth: .infinity, minHeight: viewport, alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: "clipList")
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ScrollOffsetKey.self, value: -geometry.frame(in: .named("viewport")).minY)
        })
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
        .onPreferenceChange(RowFramesKey.self) { rowFrames = $0 }
        // One gesture covers the whole list: a drag selects the clips in its range (or, starting on a
        // selected clip, deselects them) and scrolls when it nears the top or bottom edge; a click on
        // empty space clears the selection. Clicks on a clip are handled by the clip itself.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("clipList"))
                .onChanged { value in
                    guard hypot(value.translation.width, value.translation.height) >= 6 else { return }
                    dragStart = value.startLocation
                    pointerInViewport = value.location.y - scrollOffset
                    selectDragged(to: value.location.y)
                    let edge: CGFloat = 36
                    let direction = pointerInViewport < edge ? -1 : (pointerInViewport > viewport - edge ? 1 : 0)
                    autoScroller.step = { autoScroll(direction, viewport: viewport, proxy: proxy) }
                    autoScroller.run(direction != 0)
                }
                .onEnded { value in
                    autoScroller.run(false)
                    let moved = hypot(value.translation.width, value.translation.height) >= 6
                    if !moved && clip(at: value.startLocation) == nil {
                        store.tapEmptySpace()
                    }
                    dragStart = nil
                    store.endDrag()
                }
        )
    }

    private func selectDragged(to y: CGFloat) {
        guard let dragStart else { return }
        store.drag(across: clips(from: dragStart, to: CGPoint(x: dragStart.x, y: y)), startedOn: clip(at: dragStart))
    }

    /// Scrolls one row past the edge the pointer is holding, then extends the selection to whatever
    /// row is now under the pointer.
    private func autoScroll(_ direction: Int, viewport: CGFloat, proxy: ScrollViewProxy) {
        let rows = rowFrames.sorted { $0.value.minY < $1.value.minY }
        if direction > 0, let next = rows.first(where: { $0.value.maxY > scrollOffset + viewport + 1 }) {
            withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(next.key, anchor: .bottom) }
        } else if direction < 0, let previous = rows.last(where: { $0.value.minY < scrollOffset - 1 }) {
            withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(previous.key, anchor: .top) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            selectDragged(to: pointerInViewport + scrollOffset)
        }
    }

    private func row(_ item: ClipItem) -> some View {
        ClipRow(item: item,
                order: store.order(of: item.id),
                highlighted: store.highlightedID == item.id,
                store: store)
            .id(item.id)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: RowFramesKey.self,
                                       value: [item.id: geometry.frame(in: .named("clipList"))])
            })
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
    }

    private func clip(at point: CGPoint) -> UUID? {
        rowFrames.first { $0.value.contains(point) }?.key
    }

    /// Clips whose rows overlap the vertical span of a drag, nearest to its start first.
    /// Only height matters, so a drag can start beside or between clips.
    private func clips(from start: CGPoint, to end: CGPoint) -> [UUID] {
        let top = min(start.y, end.y), bottom = max(start.y, end.y)
        return rowFrames
            .filter { $0.value.maxY >= top && $0.value.minY <= bottom }
            .sorted { abs($0.value.midY - start.y) < abs($1.value.midY - start.y) }
            .map(\.key)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title.uppercased())
        }
        .font(.system(size: 10, weight: .bold))
        .tracking(0.6)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: store.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.query.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.system(size: 15, weight: .semibold))
            Text(store.query.isEmpty
                 ? "Copy anything and it will show up here."
                 : "Try a different word.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        ZStack {
            if store.selection.isEmpty {
                HStack(spacing: 14) {
                    hint("Click", "select")
                    hint("Click ×2", "copy")
                    Spacer()
                    if store.shortcutUnavailable {
                        Text("\(store.shortcut.title) is taken · change it in •••")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if store.shortcut != .off {
                        hint(store.shortcut.title, "open")
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    Button {
                        store.clearSelection()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(PressableStyle())

                    if let count = store.selectedCharCount {
                        Text(ClipboardStore.charCountLabel(count))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Menu {
                        Section("Copy As") {
                            ForEach(TextTransform.allCases) { transform in
                                Button {
                                    store.copySelection(transform: transform)
                                } label: {
                                    Label(transform.title, systemImage: transform.icon)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.07)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Copy As")

                    Button {
                        store.copySelection()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(store.selection.count == 1 ? "Copy 1 Item" : "Copy \(store.selection.count) Items")
                                .contentTransition(.numericText())
                            Text("⏎")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.7)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.8)],
                                                          startPoint: .top, endPoint: .bottom))
                        )
                        .shadow(color: .accentColor.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(PressableStyle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: store.selection.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.selection.count)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Toast

    @ViewBuilder
    private var toast: some View {
        if let message = store.toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: message)
                Text(message)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.green.gradient))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, 70)
            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Repeats a step while a drag holds the pointer near the top or bottom of the list.
@MainActor
final class DragAutoScroller: ObservableObject {
    var step: (() -> Void)?
    private var timer: Timer?

    func run(_ active: Bool) {
        guard active else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step?() }
        }
    }
}
