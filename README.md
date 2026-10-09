# ClipStack

A menu bar clipboard history for macOS. Every copy shows up in the list; click clips to select several, and they are copied back as one, in the order you clicked them.

## Build and run

```sh
./build.sh            # builds build/ClipStack.app
./build.sh --install  # also copies it to /Applications
open build/ClipStack.app
```

The app icon is drawn by `scripts/make-icon.swift`; run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns`.

## Using it

- Click the clipboard icon in the menu bar, or press ⌃⌘V anywhere.
- Click clips, or drag across them, to select them; the number on each shows its place in the order. Double-click a clip to copy just that one.
- ⏎ or **Copy N Items** copies the selection back to back with nothing in between (add line breaks, spaces or commas under the ••• menu).
- After copying, ClipStack pastes into the app you were using (needs Accessibility access once; turn off with **Paste After Copying** in the ••• menu).
- The wand button next to **Copy**, or right-clicking a clip, offers **Copy As**: trim spaces, single line, UPPERCASE, lowercase, Title Case, or remove quotes.
- **Keep History** in the ••• menu removes unpinned clips after 1 day, 1 week, or 1 month.
- Hover a clip to pin it, copy only that clip, or delete it.
- Keyboard: ↑ ↓ move, ⇥ select, ⏎ copy, ⌘P pin, ⌘⌫ delete, esc clears the selection, then the search, then closes.

Password manager copies are skipped. History is kept in `~/Library/Application Support/ClipStack/history.json` (200 clips, pinned ones never expire).
