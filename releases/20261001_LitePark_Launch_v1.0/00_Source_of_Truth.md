# LitePark v1.0.0 — Source of Truth

## Product

- **Product name:** LitePark
- **Version:** v1.0.0
- **Tag:** `v1.0.0`
- **Tagline:** Park it now. Pick it up later.
- **One-line description:** A lightweight macOS companion for parking ChatGPT conversations you want to return to later.
- **Platform:** macOS only
- **Minimum version:** macOS 13
- **License:** MIT
- **Repository:** https://github.com/victor-zhang-2026/LitePark
- **Release:** https://github.com/victor-zhang-2026/LitePark/releases/tag/v1.0.0
- **Download:** https://github.com/victor-zhang-2026/LitePark/releases/download/v1.0.0/LitePark-v1.0.0-macOS.zip

## Problem

ChatGPT history keeps conversations, but it does not provide a focused queue for conversations that should be handled later. Useful research, learning threads, travel plans, reading notes, and side-project ideas can disappear into history before the user returns to them.

## What LitePark does

LitePark adds a small local queue beside ChatGPT Desktop:

1. Open a conversation in ChatGPT.
2. Press `⌃⌥L` to park it.
3. Open LitePark with its floating trigger or `⌃⌥K`.
4. Reorder parked conversations manually.
5. Open one back in ChatGPT or mark it done.

## Current features

- Capture the active ChatGPT Desktop conversation title
- Prevent duplicate titles in the queue
- Add new items to the top
- Manually reorder using a hover-revealed drag handle
- Open a saved conversation in ChatGPT and verify the destination
- Mark items done
- Persist the queue and manual order locally
- Move the floating trigger across displays
- Global shortcuts: `⌃⌥L` and `⌃⌥K`
- Accessibility permission guidance
- Launch at Login control

## Requirements

- macOS 13 or later
- ChatGPT Desktop for macOS
- ChatGPT Desktop must be running while adding or opening conversations
- Accessibility access for LitePark

## Installation

Download and unzip the release, move LitePark to Applications, then right-click and choose **Open** on first launch. v1.0.0 is not Apple-notarized, so Gatekeeper may require **Open Anyway** in Privacy & Security.

## Privacy

LitePark is local-only. It stores a local item ID, conversation title, added timestamp, and manual order. It stores no conversation content, screenshots, account data, analytics, or telemetry.

All public examples and images use fictional demo titles. Public materials contain no real conversation names or local user paths.

## Known issues

- LitePark v1.0.0 identifies conversations by title.
- Users should give a conversation its intended name before adding it and avoid renaming it afterward.
- Duplicate titles are ambiguous.
- Automatic reopening requires one exact matching title to be exposed in ChatGPT Desktop's current sidebar accessibility tree.
- The release is not notarized by Apple.

The title mechanism is planned for improvement; there is no committed date.

## Audience and scenarios

People who use ChatGPT Desktop across multiple ongoing topics and want a small, manual “come back later” queue. Safe public examples include product research, trip planning, books, learning, recipes, and side-project notes.

## Calls to action

- **Primary:** Download LitePark v1.0.0 and try it on macOS.
- **Secondary:** Star the repository, report issues, and share workflow feedback.

## Public demo names

- Product Research
- Weekend Trip Ideas
- Books to Read
- AI Tools to Try

No other conversation names should appear in public assets.

