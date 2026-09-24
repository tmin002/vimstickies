# VimStickies

A lightweight, native macOS sticky note app with vi keybindings.

## Requirements

- macOS 26 or later
- Swift 6.2 or later
- Xcode 26 or later for app packaging and distribution

## Development

```sh
swift build
swift run
swift run VimBridgeCheck
```

Opening `Package.swift` in Xcode provides the normal AppKit development and debugging workflow.

## Architecture

- AppKit owns windows, text input, accessibility, and the application lifecycle.
- `NSTextView` provides the native plain-text editing surface and IME integration.
- The UI follows the compact, single-color macOS Stickies layout without glass effects.
- A thin C bridge isolates Swift from libvim's internal headers and global state.

## libvim

The current integration target is `onivim/libvim` at commit
`9ade7d1e2ac54cb945724762cb8be9c68adef3f0`.

The pinned Apple Silicon `libvim.a` is stored under `Vendor/LibVim`. It targets
macOS 26 and is linked through the `CVimBridge` Swift Package target. The bridge
has tests for motions, insert mode, visual mode, Unicode text, and multiple notes.

Rebuild the pinned library with:

```sh
sh Scripts/build-libvim.sh
```

libvim will remain an implementation detail. Vim buffers, command-line editing,
plugins, splits, and tabs are not user-facing VimStickies features.

Normal and Visual mode commands run in libvim. Insert mode text entry runs through
`NSTextView` so macOS input methods can manage marked text, and is committed back
to libvim when leaving Insert mode.

## Current vi surface

- Normal, Insert, Visual, and Visual Line modes
- libvim motions and operators, including counts
- Native macOS text entry and IME composition in Insert mode
- `:`, `/`, and `?` are intentionally disabled until command UI exists
