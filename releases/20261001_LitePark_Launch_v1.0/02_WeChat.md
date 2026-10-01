# 微信公众号发布材料

## 标题候选

1. **产品型：** 我做了一个 ChatGPT Desktop 的“稍后处理”工具：LitePark
2. **场景型：** 那些现在不想处理、但不能忘记的 ChatGPT 对话
3. **Builder 型：** 用 Vibe Coding 做完并开源了 LitePark v1.0.0

**推荐：** 那些现在不想处理、但不能忘记的 ChatGPT 对话

## 摘要

我做了一个 macOS 小工具 LitePark，把暂时处理不了、之后还要回来的 ChatGPT 对话放进一个轻量队列。v1.0.0 现已开源，可以直接从 GitHub 下载体验。

## 正文

我在 ChatGPT Desktop 里同时保留着不少对话：有些是产品调研，有些是准备继续看的资料，也有些只是一个暂时没空展开的想法。

真正麻烦的并不是“找不到历史记录”，而是历史记录无法表达一个很具体的状态：

> 这段对话我现在不处理，但之后一定要回来。

收藏、置顶或者未读都不完全等于这个意思。于是我做了 LitePark。

LitePark 是一个 macOS 上的轻量浮窗。打开一个 ChatGPT 对话后，按下 `⌃⌥L`，它就会进入 LitePark。之后可以在浮窗里手动调整顺序、重新打开对话，或者处理完以后直接勾掉。

整个流程很短：

1. 在 ChatGPT Desktop 打开一段对话；
2. 按 `⌃⌥L` 加入 LitePark；
3. 通过悬浮球或 `⌃⌥K` 打开列表；
4. 点击标题回到 ChatGPT，或勾选 Done。

我希望它像一个安静的桌面工具：平时只留下一个可以移动的悬浮球，需要时才展开。列表顺序完全由自己决定，没有优先级、标签、提醒、AI 总结，也没有把它扩展成另一个任务管理器。

这次 v1.0.0 包含这些能力：

- 保存当前 ChatGPT 对话；
- 手动拖拽排序；
- 重新打开对应对话；
- 完成后从列表移除；
- 本地保存队列与顺序；
- 跨显示器移动悬浮球；
- 全局快捷键操作。

LitePark 只在 Mac 上运行，需要 ChatGPT Desktop 已经启动，并需要 macOS Accessibility 权限。它只在本地保存对话标题、排序和必要的队列元数据，不读取或保存对话正文，也没有统计或遥测。

当前还有一个明确限制：v1.0.0 依赖对话名称进行识别。比较稳妥的用法是先在 ChatGPT 里把对话名改好，再加入 LitePark；加入后暂时不要再次改名。重名对话也可能无法自动判断。这个机制后续还会继续优化。

为什么现在发布？因为它已经能够完成我最初想解决的那条完整路径：

> 当前对话 → 先放一边 → 稍后打开 → 处理完成。

这也是一次很具体的 Vibe Coding 实践。重点不在于把功能越做越多，而是不断拿真实使用中的失败反馈去修正窗口交互、拖拽、快捷键和 ChatGPT 跳转，最后把范围收在一个每天能用的小工具上。

LitePark v1.0.0 已开源：

- GitHub：https://github.com/victor-zhang-2026/LitePark
- 下载：https://github.com/victor-zhang-2026/LitePark/releases/tag/v1.0.0

如果你也有“这段 ChatGPT 对话之后还要回来”的场景，欢迎下载试试。遇到问题可以提交 Issue，也欢迎告诉我你实际会怎么用它。觉得有用的话，可以顺手 Star。

## 图片顺序

1. `wechat/cover-900x383.png` — 公众号头条封面
2. `wechat/images/product-demo-queue.png` — 使用虚构 Demo 数据的真实队列界面
3. `xiaohongshu/images/03-workflow.png` — 加入、返回和 Done 流程
4. `xiaohongshu/images/05-privacy.png` — 本地隐私说明
5. `xiaohongshu/images/06-open-source.png` — GitHub 与下载 CTA

可直接预览和复制的完整排版稿位于 `wechat/article.html` 与 `wechat/article-wechat-copy.html`。所有对话名称均为虚构 Demo 数据。

## CTA

**下载 LitePark v1.0.0 → 体验 → Star → 提交 Issue / 反馈实际工作流。**
