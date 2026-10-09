import SwiftUI

struct ContentView: View {
    static let width: CGFloat = 380
    static let height: CGFloat = 540

    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool

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
                Text(store.items.isEmpty ? "Waiting for your first copy" : "\(store.items.count) clips")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Join Multiple Items With", selection: $store.separator) {
                ForEach(JoinSeparator.allCases) { Text($0.title).tag($0) }
            }
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4, pinnedViews: []) {
                        if !pinned.isEmpty {
                            sectionTitle("Pinned", icon: "pin.fill")
                            ForEach(pinned) { row($0) }
                            if !recent.isEmpty { sectionTitle("Recent", icon: "clock") }
                        }
                        ForEach(recent) { row($0) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: store.highlightedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        ClipRow(item: item,
                order: store.order(of: item.id),
                highlighted: store.highlightedID == item.id,
                store: store)
            .id(item.id)
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
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
                    hint("⏎", "copy")
                    hint("⇥", "select")
                    Spacer()
                    hint("⌃⌘V", "open")
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

                    Spacer()

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
