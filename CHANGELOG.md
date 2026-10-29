# Changelog

## 1.0.3 — 2026-10-29

- 修复合盖、外接屏及屏幕布局切换后的悬浮球错位，按显示器保存相对位置。
- 修复外接屏拖动不跟手，按鼠标起点计算目标位置，避免逐帧累积偏移。
- Preserve display-relative floating-ball positions across clamshell and monitor-layout changes. Anchor dragging to the initial pointer position for reliable external-display movement.
