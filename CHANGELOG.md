# Changelog

## 1.1.0 — 2026-11-02

- Replace the vertical queue with a compact two-column Parking Board. Cards have individual bay outlines, small striped stops, and up to two empty-space previews.
- Reorder cards across rows and columns with live previews; the manual order is saved on release.
- Add Card Limit to Settings: 6, 9, 12, 16, or 20 cards, with a default of 12. The header shows current usage and capacity.
- Show a brief “Card limit reached.” message when full. Lowering the limit preserves every existing card and Undo restoration.
- Retain conversation capture/reopen, Done/Undo, shortcuts, the floating trigger, and existing branding.

## 1.0.3 — 2026-10-29

- 修复合盖、外接屏及屏幕布局切换后的悬浮球错位，按显示器保存相对位置。
- 修复外接屏拖动不跟手，按鼠标起点计算目标位置，避免逐帧累积偏移。
- Preserve display-relative floating-ball positions across clamshell and monitor-layout changes. Anchor dragging to the initial pointer position for reliable external-display movement.
