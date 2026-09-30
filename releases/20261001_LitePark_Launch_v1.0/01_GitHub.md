# GitHub Launch

## Repository metadata

- **Name:** LitePark
- **Description:** A lightweight macOS companion for parking ChatGPT conversations you want to return to later.
- **Topics:** `macos`, `chatgpt`, `productivity`, `desktop-app`, `swift`, `swiftui`
- **Homepage:** Leave empty; there is no separate product website.
- **License:** MIT

## Release

- **Tag:** v1.0.0
- **Title:** LitePark v1.0.0
- **Asset:** LitePark-v1.0.0-macOS.zip
- **SHA-256:** `b42a27288a15c7feea170d7c184a105c1218bebc353d9163f533f705a31a7834`

## Release notes

LitePark is a lightweight macOS companion for parking ChatGPT conversations you want to come back to later.

Press `⌃⌥L` while a conversation is open in ChatGPT Desktop. LitePark adds it to a small floating queue where you can reorder it, open it again, or mark it done.

### What is included

- Add the current ChatGPT conversation with a global shortcut
- Open a compact floating queue with `⌃⌥K`
- Drag conversations into your preferred manual order
- Reopen a saved conversation in ChatGPT Desktop
- Mark a conversation done
- Keep queue data locally on your Mac
- Move the floating trigger across displays

### Requirements

- macOS 13 or later
- ChatGPT Desktop for macOS
- ChatGPT Desktop must be running while adding or opening conversations
- Accessibility permission for LitePark

### Get started

1. Download `LitePark-v1.0.0-macOS.zip`.
2. Unzip it and move `LitePark.app` to Applications.
3. Right-click LitePark and choose **Open** on first launch.
4. Grant Accessibility access.
5. Start ChatGPT Desktop and press `⌃⌥L` on a conversation you want to park.

The v1.0.0 build is not Apple-notarized. macOS may require **Open Anyway** under System Settings → Privacy & Security.

### Known issue: conversation names

LitePark v1.0.0 identifies conversations by title. Give a conversation a useful name before adding it, then avoid renaming it in ChatGPT afterward. Duplicate titles are ambiguous. This mechanism is planned for improvement in a future version.

Automatic reopening also requires one exact matching conversation to be visible to macOS Accessibility in ChatGPT's current sidebar.

Feedback and issue reports are welcome: https://github.com/victor-zhang-2026/LitePark/issues
