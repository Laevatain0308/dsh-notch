# DSH Notch

A native macOS companion for DeepSeek Harness: live task counts, decisions, results, and a playful idle robot. Built with AppKit, SwiftUI, and Canvas. The helper does not run a browser or call a model.

DSH 的原生 macOS 任务胶囊：显示运行任务、待决策、未读成功和失败；空闲时出现机器人。点击选项直接回答，点击问题标题返回 DSH 查看上下文。

## What's new in 0.3.0 / 本次更新

- Running → decision shares the travelling brush used for success and failure. Single-task and concurrent-task cases preserve the right counts.
- Decision → running has a continuous return path. Fast replies queue behind the outgoing stroke; stale callbacks cannot replay a completed transition.
- Nine idle motions, blinking, and the chameleon easter egg share the production robot renderer. Idle pauses last 5–10 seconds; dance lasts 3–5 seconds.
- A standalone recording app includes **36 scenes with Chinese and English titles**, in a six-tile grid or a single-scene view.
- Long questions grow to the screen limit, then scroll; short questions shrink again. Long Markdown keeps its choices below the scrolling detail.

蓝色到黄色、黄色返回蓝色已接入正式 helper，覆盖单任务、多个任务和快速回复。机器人、成功与失败、未读清除、任务增减都可在离线演示里循环录屏。

## Try the recording demo / 先看演示

Requires macOS 14+, Swift 6 Command Line Tools, and Python 3. The application targets macOS 14+; native visual regression checks must be run on the target OS.

```sh
git clone https://github.com/aa2246740/dsh-notch.git
cd dsh-notch
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
sh tools/recording/build.sh
open "dist/DSH Notch Demo.app"
```

The demo copies the current production animation sources at build time and substitutes a local transport stub. It does not connect to DSH, send real answers, or spend model tokens.

| Key | Action / 操作 |
| --- | --- |
| ← / → | Previous / next group · 上一组 / 下一组 |
| S | Grid / single scene · 六格 / 单场景 |
| R | Replay · 重播 |
| H | Show / hide controls · 显示 / 隐藏控制栏 |
| Control + Command + F | Full screen · 全屏 |

Only the visible scenes animate. Disable “全部连播” to loop one group. See [recording instructions](tools/recording/README.md).

## Connect to DSH / 连接真实任务

The Host plugin depends on the existing Cordis services `sessions`, `webServer`, `approval`, `userQuestions`, and `agents`. It is not a standalone Web server and does not modify official Harness source. Compatibility depends on these Host interfaces; this release is not a blanket certification of every DSH version or desktop shell.

For an existing dshx-managed installation, inspect the target and change surface before activation:

```sh
dshx status dsh-notch
dshx activation-plan dsh-notch --change artifact
```

Native-helper updates replace the executable **and its resource bundle**, then relaunch only that helper. Host-plugin source updates require their own activation plan. Do not assume copying a file reloads Host modules.

Build the helper:

```sh
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build --package-path macos -c release
macos/.build/release/dsh-notch --verify-idle-resources
macos/.build/release/dsh-notch
```

`--verify-idle-resources` should print `IDLE_RESOURCES=10/10`. When installing elsewhere, keep `DshNotch_DshNotch.bundle` next to `dsh-notch`. Avoid launching a second helper while a shell-managed copy is running.

The helper reads the loopback origin and authentication token from `~/.dsh/dsh-notch/runtime.json`, written by the Host plugin. Keep that file private. It connects to the existing Host and never starts another DSH server.

## Motion and layout / 动效与布局

A short brush leaves the current blue orbit and paints the destination: green above for done, red below for failed, yellow for a decision. It returns to blue only while work remains. Outbound status motion takes 0.95 seconds. Replies preserve the source count until the stroke rejoins the running orbit.

The idle robot uses sampled vector outlines with per-frame interpolation. Incoming work interrupts its current pose, folds the robot back into a point, and draws the new status. After every result is read, the robot rotates and grows back into view. Reduced Motion presents static final states.

Compact height follows visible status slots. Expanded height follows content, capped by equal top and bottom screen insets. The native panel preserves its upper-right anchor during resizing.

See [motion contracts](macos/STATUS-MOTION.md), [design notes](DESIGN.md), and [robot resources](tools/idle/).

## Development / 开发验证

Node.js with `--import` support is required for Host unit tests. Native tests need macOS and Swift Command Line Tools.

```sh
npm ci
npm test
npm run test:outcome
npm run test:motion
npm run test:geometry
npm run test:scrollbar
npm run test:idle
npm run build:macos
npm run build:demo
```

These checks use offline fixtures. They cover state transitions, brush continuity, fast replies, cancellation, window geometry, and robot resources. Actual session focus, Host approvals, keyboard input, and multiple displays need separate live acceptance.

Optional desktop renderer diagnostics and recovery tools live in [tools/desktop-shell](tools/desktop-shell/README.md). They belong to the desktop shell, not the native animation runtime. Logging or reloading a blank renderer does not establish its underlying cause.

## License / 开源许可

[MIT](LICENSE). Robot assets derive from [OpenBotMotion](https://github.com/aa2246740/open-bot-motion); its original [MIT notice](tools/idle/LICENSE.open-bot-motion) is retained. This is an independent community companion, not an official DeepSeek application.
