# LinkedIn Launch Material

ChatGPT history keeps conversations, but it does not express a simple intention: I cannot deal with this now, and I need to come back later.

That gap led me to build LitePark, a small macOS companion for ChatGPT Desktop.

With one shortcut, the current conversation moves into a lightweight floating queue. From there, I can place conversations in a manual order, open one back in ChatGPT, or mark it done. The app stores only local queue metadata and does not collect conversation content or analytics.

The product constraint was intentional. LitePark does not try to become another task manager. It focuses on one loop:

Park a conversation → return later → finish it.

Building v1.0.0 through Vibe Coding was less about generating a large feature set and more about tightening real desktop behavior: global shortcuts, draggable floating windows, persistent ordering, macOS Accessibility, and reliable navigation back into ChatGPT.

The current version has a clear limitation: it identifies conversations by title. Users should name a conversation before adding it and avoid renaming it afterward. Duplicate titles are also ambiguous. I am documenting that constraint rather than hiding it, and the mechanism can improve in future versions.

LitePark v1.0.0 is now open source for macOS 13+.

Repository and download:
https://github.com/victor-zhang-2026/LitePark

If this matches your ChatGPT workflow, I would value practical feedback: where does the interaction feel natural, and where does it get in your way?

#macOS #ChatGPT #VibeCoding #OpenSource #ProductDesign #SwiftUI

