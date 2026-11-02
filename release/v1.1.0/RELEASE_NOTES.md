# LitePark 1.1.0 · Parking Board

Park it now. Pick it up later.

- **Parking Board:** two-column conversation cards with individual parking bays, small striped stops, and empty-space previews.
- **Manual order:** drag a card’s hover handle across rows and columns. Other cards make room, and the order is saved when you release.
- **Card Limit:** choose 6 / 9 / 12 / 16 / 20 in Settings. The default is 12, and the header shows current cards / capacity.
- **Full-board feedback:** new cards are paused when full. Existing cards stay intact when you lower the limit, including Undo restoration.

Conversation capture and reopen, Done/Undo, global shortcuts, floating-trigger behavior, and branding remain in place.

## Reopening conversations

Keep the target conversation visible in ChatGPT’s sidebar. Expand its project or chat group first if it is collapsed.

## Install

Download `LitePark-v1.1.0-macOS.zip`, unzip it, and replace `LitePark.app` in Applications. Existing saved conversations and preferences are retained.

Requires Apple silicon and macOS 13 or later. This build is signed with a local development identity and is not Apple-notarized.

## Validation

The owner accepted the functionality and final appearance on the local build. Earlier isolated capacity/persistence checks passed 190 assertions, and the existing panel-lifecycle checks passed. This release adds packaging and signature/integrity verification; no additional interaction tests were run.
