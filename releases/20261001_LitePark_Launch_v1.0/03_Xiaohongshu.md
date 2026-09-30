# 小红书发布材料

## 标题候选

1. 我给 ChatGPT 对话做了一个“稍后处理”浮窗
2. ChatGPT 对话太多，我做了 LitePark
3. 一个周末型小工具：把 ChatGPT 对话先停在这里

**推荐：** 我给 ChatGPT 对话做了一个“稍后处理”浮窗

## 正文

我经常在 ChatGPT Desktop 里开着很多对话。

有些现在没空继续，但又不想让它沉进历史记录。它们可能是一次产品调研、一份阅读清单、旅行计划，或者一个之后要继续验证的想法。

所以我做了 LitePark，一个 macOS 上的 ChatGPT “稍后处理”小工具。

打开一段对话，按 `⌃⌥L` 就能放进 LitePark。之后可以：

- 手动拖拽排序
- 点击标题回到对应对话
- 处理完直接勾掉
- 用一个可移动的悬浮球随时打开列表

它只做这一件事，没有标签、优先级、提醒和 AI 总结。我更希望它像桌面上的一个小停车位，需要的时候出现，平时安静待着。

这个项目也是一次比较真实的 Vibe Coding：拖拽、浮窗、快捷键、后台唤起 ChatGPT，都不是第一版就顺利。v1.0.0 终于把最核心的流程跑通了，所以先开源出来。

使用条件：

- 目前只支持 macOS
- 需要安装并启动 ChatGPT Desktop
- 需要给 LitePark Accessibility 权限
- 当前依赖对话名称识别：建议先改好名称再加入，加入后暂时别再次改名

LitePark 不保存对话正文，也没有统计或遥测。队列信息只存在本地。

GitHub 和下载：
https://github.com/victor-zhang-2026/LitePark

如果你也经常有“这个对话之后再看”的情况，欢迎试用，也欢迎把不顺手的地方告诉我。

## 封面文案

**主标题：** ChatGPT 对话，先停在这里

**副标题：** LitePark · macOS 对话停车位

## 图片顺序

1. 封面：App Icon + “ChatGPT 对话，先停在这里”
2. 使用虚构 Demo 数据的 LitePark 队列
3. 悬浮球与展开面板
4. “添加 → 排序 → 打开 → Done”流程卡
5. 快捷键与 macOS / ChatGPT Desktop 要求
6. GitHub 下载页

## Hashtags

#LitePark #macOS软件 #ChatGPT #独立开发 #VibeCoding #效率工具 #开源项目
