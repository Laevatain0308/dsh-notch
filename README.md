# dsh-notch

贴边 notch：只显示 **正在跑的对话** 和 **未读结果**（成功/失败），有审批或模型提问时胶囊会动，可以在条里处理。

不改 DeepSeek Harness 源码。Host plugin 挂在现有 Web Host 上；原生 helper 是旁边一个小进程。DSH.app 可以没有。

## 启用 plugin（保持当前 Host PID）

```sh
dshx check dsh-notch
dshx sync-artifact dsh-notch
# 然后按 activation-plan 的 patch 分支热挂，不要重启 adopted Host
```

## 打开 notch

需要本机 Command Line Tools（已有 Swift 即可，不要 Xcode.app）：

```sh
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT="$(xcrun --show-sdk-path)"
cd macos
swift build -c release
./.build/release/dsh-notch
```

Helper 读 `~/.dsh/dsh-notch/runtime.json`（plugin 写入的 loopback origin + token），连当前 Host，不会自己再起一份 DSH。

## 原生尺寸动画回归

窗口统一控制 200 ms 的尺寸过渡，每帧固定右上角；SwiftUI 外壳填满当前窗口，展开内容不会撑大外壳的最小宽度。快速反向移动会取消旧动画，系统开启减少动态效果时立即改变尺寸。

运行 `sh macos/Tests/geometry.sh` 可离线检查 hover、快速反向、展开和收起时的右边缘、左圆角及窗口锚点。该测试渲染真实原生组件，不连接 Host、不调用模型；不能替代真实会话跳转、审批、提交失败重试和多显示器验收。

展开高度随内容增长，上限为当前屏幕可用高度减去上下相同的 100 点边距。超过上限才滚动；短内容自动收紧。屏幕参数变化时重新计算高度上限。

状态动效：运行弧线向上转绿表示完成，向下转红表示失败，结果圈显示对应数量；仍有任务时回到蓝色运行圈。动效只响应新状态变化，连续结果依次播放，减少动态效果下直接呈现数量。动效时序见 `macos/STATUS-MOTION.md`。

## 开发与验证

Host 端需要现有 DeepSeek Harness / Cordis 环境，不是独立 Web 服务。

```sh
npm install
npm test
npm run test:motion
npm run test:geometry
npm run build:macos
```

原生测试需要 macOS 和 Swift Command Line Tools，不连接 DSH、不调用模型。
初始基线 `e32b9d7` 不含机器人；后续版本的待机实现见下文。

## 待机机器人

无运行任务、待回答问题、审批和未读结果时显示浅色机器人。9 个基础动作每隔 20–45 秒随机触发、不连续重复；变色舞蹈使用原库原速，每隔 20–40 分钟可见待机触发。屏幕休眠停止动画，不补播积压动作。

右键机器人可选“试试下一个待机动作”或“播放变色跳舞彩蛋”。系统开启减少动态效果时保持静态。来任务约 300 ms 收拢成运行圆弧，所有结果读完后约 400 ms 从点展开；真实任务不会等待动画。

原生 Canvas 使用离线采样的矢量轮廓并在显示帧间插值，不创建浏览器进程。资源基于 OpenBotMotion（MIT）；原始库、9 个原创姿态时间轴、授权与导出脚本见 `tools/idle/`。`sh macos/Tests/idle.sh` 验证资源、裁切与中断反向。

安装 helper 时须将构建目录里的 `DshNotch_DshNotch.bundle` 和 `dsh-notch` 一起放入目标目录，不能只复制可执行文件。运行 `dsh-notch --verify-idle-resources` 应输出 `IDLE_RESOURCES=10/10`。
