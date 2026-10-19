# ClipPeekQueueMini — specification

**Tagline:** Preview what is on your clipboard in a tiny floating tip before you paste, with formats and size shown.

**Category:** Clipboard

**Inspired by (paid):** Paste Plain Hotkey: Pure Paste ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, UniformTypeIdentifiers, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Pure Paste is a small Mac utility sold for about 5 dollars that pastes clipboard content without formatting through a hotkey, and similar tiny paste helpers are regularly listed in Mac utility roundups because people constantly need to see and control what is about to be pasted. Our clean-room version goes in a different direction from history managers: it is a clipboard inspector that shows exactly what is on the pasteboard right now, in every format, and lets you strip it down to one format with a keystroke.

Feature set: A hotkey, default Control Option V, shows a small floating tip near the pointer for a few seconds describing the current clipboard: a preview of text or image, character or pixel size, byte size and the list of data types present such as plain text, rich text, HTML, PNG and file URLs. Buttons in the tip let the user reduce the clipboard to plain text, to the first file path only, to an image converted to PNG, or to a trimmed single line. A second hotkey, default Control Option Shift V, performs the plain text reduction and immediately pastes it into the frontmost app. A small log of the last five reductions can be undone by restoring the original contents. Around 350 lines.

UI spec: MenuBarExtra shows a live summary of the clipboard in the menu with an icon that changes with content type. Menu items: Inspect Clipboard, Paste as Plain Text, Undo Last Reduction, Settings, Quit. Settings fields: both hotkeys, tip duration, whether to auto reduce every copy to plain text, a list of apps where automatic reduction is disabled, and launch at login. Empty state: when the clipboard is empty the tip says clipboard is empty. The tip panel is a nonactivating floating panel with a material background and buttons that are keyboard reachable via the letters P, F, I and T.

Technical approach: Read NSPasteboard types and for each type obtain data length. Map types to friendly names with UniformTypeIdentifiers. Build preview images with NSImage and limit to a thumbnail. Plain text reduction reads the string representation and writes it back after clearing contents, while preserving the original items in memory for undo. Auto reduce mode uses changeCount polling and skips content from concealed marker types. Pasting uses CGEvent Command V with Accessibility permission requested lazily the first time paste is used, with an explanation panel. Hotkeys use Carbon. Settings stored with AppStorage and launch at login with SMAppService.

Edge cases: Pasteboard items may be promised and not yet materialized, so reading data lazily could be slow, hence read only type names unless the user asks for a preview. Avoid infinite loops in auto mode by ignoring changes the app made. Large images should not be converted on the main thread. If another app changes the clipboard between inspect and reduce, act on the latest content and update the tip. Without Accessibility, the paste hotkey falls back to reducing and shows a notice to press Command V manually.
