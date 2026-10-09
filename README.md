# ClipStack

A menu bar clipboard history for macOS. Every copy shows up in the list. Pick several clips, by clicking or dragging, and ClipStack copies them back as one, in the order you picked them.

<p align="center"><img src="docs/demo.gif" alt="Selecting three clips in order and copying them as one" width="520"></p>

## Install

Requires macOS 14 or later on Apple silicon.

**Homebrew**

```sh
brew install --cask neul-lov/tap/clipstack
```

**Download**

Grab `ClipStack.dmg` from the [latest release](https://github.com/neul-lov/ClipStack/releases/latest), open it, and drag ClipStack into Applications.

ClipStack isn't notarized yet, so macOS warns about an unidentified developer the first time. Right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/ClipStack.app
```

## Using it

- Click the clipboard icon in the menu bar, or press ⌃⌘V anywhere.
- Click clips, or drag across them, to select them; the number on each shows its place in the order. Double-click a clip to copy just that one. Click empty space to clear the selection.
- ⏎ or **Copy N Items** copies the selection back to back with nothing in between (add line breaks, spaces or commas under the ••• menu). The footer shows the character count, spaces included.
- After copying, ClipStack pastes into the app you were using (needs Accessibility access once; turn off with **Paste After Copying** in the ••• menu).
- The wand button next to **Copy**, or right-clicking a clip, offers **Copy As**: trim spaces, single line, UPPERCASE, lowercase, Title Case, or remove quotes.
- **Keep History** in the ••• menu removes unpinned clips after 1 day, 1 week, or 1 month.
- Hover a clip to pin it, copy only that clip, or delete it.
- Keyboard: ↑ ↓ move, ⇥ select, ⏎ copy, ⌘P pin, ⌘⌫ delete, esc clears the selection, then the search, then closes.

Password manager copies are skipped. History stays on your Mac in `~/Library/Application Support/ClipStack/history.json` (200 clips; pinned ones never expire).

## Build from source

```sh
./build.sh            # builds build/ClipStack.app
./build.sh --install  # also copies it to /Applications
./build.sh --dmg      # also packages build/ClipStack.dmg
```

The app icon is drawn by `scripts/make-icon.swift`; run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns`. The demo GIF comes from a debug build: `swift build && .build/debug/ClipStack --demo` plays a scripted walkthrough with sample clips.
