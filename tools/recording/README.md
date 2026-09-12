# Bilingual recording demo / 双语录屏演示

Build from the current production animation sources:

```sh
npm run build:demo
open "dist/DSH Notch Demo.app"
```

36 scenes in six groups cover idle, working, decisions and resume, success, failure, unread clearing, nine robot motions, and the chameleon easter egg. Chinese and English titles share one fixed title area. The demo uses local fixtures and a transport stub; it does not connect to DSH or use model tokens.

共 6 组、36 个场景。中文在上、英文在下，仅保留状态名称。动画源与正式 helper 相同，演示仅用本地假任务驱动，不连接 DSH。

| Key | Action / 操作 |
| --- | --- |
| ← / → | Previous / next group · 上一组 / 下一组 |
| R | Replay · 重播 |
| S | Grid / single scene · 并排 / 单场景 |
| H | Show / hide controls · 显示 / 隐藏控制栏 |
| Control + Command + F | Full screen · 全屏 |
| Command + Q | Quit · 退出 |

Disable “全部连播” to keep looping the selected group. Move the pointer away and hide the controls before recording. The regular helper and DSH can remain running.
