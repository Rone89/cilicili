# Video Detail Release Candidate Acceptance

基线提交：`2896eeb9b2bed3b353ed86f86c1ede15c5e60962`

验收工具链：Xcode 26.6 (17F113)，`/Applications/Xcode.app/Contents/Developer`，iOS deployment target 26.1，Swift language mode 5，设备族 `1,2`。

## 验收矩阵

| 设备 | 系统 | 结果 | 证据 |
| --- | --- | --- | --- |
| iPhone 17 Pro 模拟器 | iOS 26.5 (23F77) | 通过 | `/tmp/cilicili-phase4-iphone-final2-471-20260909.xcresult`，VideoDetail UI 10/10 |
| iPad Pro 11-inch (M5) 模拟器 | iOS 26.5 (23F77) | 通过 | `/tmp/cilicili-phase4-ipad-final2-471-20260909.xcresult`，VideoDetail UI 10/10 |
| RCe2026 实体 iPhone Air | iOS 27.0 (24A5430a) | 部分可用，交互未验收 | 可连接并安装 build 471；仅完成 `devicectl` 启动、方向命令和截图 |
| 实体 iPhone iOS 26 | iOS 26 | 未验证 | 设备不可用 |
| 实体 iPad | iPadOS 26 | 未验证 | 设备不可用 |
| iPad 分屏 | iPadOS 26 | 未验证 | 无可用实体窗口环境 |
| Stage Manager | iPadOS 26 | 未验证 | 无可用实体窗口环境 |

iOS 27 实体机的待执行人工步骤：真实播放后依次验证播放中旋转、清晰度切换中旋转、PiP 进入/返回/关闭、后台恢复、旋转中返回，以及 VoiceOver 下返回、全屏、弹幕、设置、Tab 和弹窗焦点。`devicectl` 的启动、截图和方向命令不作为这些交互通过的证据。

## 诊断与性能

`VideoDetailRotationDiagnosticRecord` 保留 rotation phase、PlayerStateViewModel/AVPlayer/AVPlayerItem/surface identity、surface attach/detach、playback state、buffering、首帧耗时和黑帧耗时字段。当前没有观测到可确认的黑帧事件，因此黑帧字段保持 `null`，没有填入零。

一次 iOS 26.5 模拟器真实播放日志样例：首播 2761.2 ms，首帧 3373.1 ms；Player、AVPlayer、AVPlayerItem 和 surface identity 在快速旋转中保持不变。当前样本旋转耗时为 771.6、565.3（superseded）、617.1、591.7 ms。基线工作树 `017ed35a` 的历史样本中位数为 984.9 ms，当前样本所有记录中位数为 604.4 ms、完成记录中位数为 617.1 ms；两组媒体、缓存和网络条件未严格同步，因此不据此宣称性能提升或调整动画参数。

Instruments 诊断使用同一 Xcode 26：

```text
xcrun xctrace version -> 16.0 (17F113)
xcrun xctrace list templates -> 可枚举 Time Profiler、SwiftUI、System Trace 等标准模板
xcrun xctrace record --template 'Time Profiler' ... -> 录制结束阶段挂起
xcrun xctrace record --template 'Time Profiler' --device <simulator> --attach <pid> ... -> 同样无法完成
xcrun xctrace export --toc ... -> Document Missing Template Error
```

Xcode 26 的标准模板由 `xctrace` 内置枚举提供，预期的 `/Applications/Xcode.app/Contents/Developer/usr/share/xctrace/templates` 路径不存在。未导出有效 trace，因此没有 CPU、内存、SwiftUI 重算或 AVPlayerLayer 性能结论。

## 测试与构建

- Debug 模拟器构建：通过，Xcode 26，iOS 26.5，build 471。
- Release arm64 模拟器构建：通过，Xcode 26，`-sdk iphonesimulator -arch arm64`，build 471。
- VideoDetail UI：iPhone 17 Pro 10/10、iPad Pro 10/10 的已归档结果通过；本轮重新启动的 UI 测试因 `simctl diagnose`/LLDB DebuggerVersionStore 环境错误生成损坏 result bundle，未将其作为新的通过结果。
- 诊断和布局单元测试：32/32 通过，`/tmp/cilicili-rc-diag-471.xcresult`。
- 全量单元测试：665 通过、3 个基线失败、共 668 项。

已知排版基线失败：

1. `PlayerFormalPlaybackConfigurationTests/testNativeTypographyMapsRolesToSystemStylesAndConservativeWeights()`：`UICTFontTextStyleSubhead` 与 `UICTFontTextStyleBody` 不一致。
2. `PlayerFormalPlaybackConfigurationTests/testNativeTypographyUsesPreferredUIKitFontAndResetsRichTextLineSpacing()`：15.0 与 17.0 不一致。
3. `PlayerFormalPlaybackConfigurationTests/testRetiredTypographyKeyDoesNotChangeNativeTypography()`：15.0 与 17.0 不一致。

这些失败来自既有排版基线，本轮未修改视频详情页代码绕过。构建日志还保留既有测试 target 的 MainActor 警告和运行时 `Publishing changes from within view updates` 警告。

## UIKit 边界与生命周期

- `VideoDetailRotationBridgeViewController`：方向锁、系统 `viewWillTransition`、状态栏/Home Indicator、生命周期和返回手势恢复。
- `VideoDetailShellSurfaceHost`：持有稳定的 `VideoSurfaceContainerView`、AVPlayer surface 和 overlay hosting。
- `VideoDetailShellSurfaceRepresentable`：SwiftUI 到 UIKit 的最小 surface bridge，负责 attach/detach 生命周期。
- `VideoDetailSwiftUIContainer`：详情页布局、Tab、Sheet、滚动和内容状态。

单纯旋转不重建播放器、AVPlayerItem 或 surface；清晰度切换允许既有设计替换 Player/Item，但 surface 保持稳定。当前没有可用实体 iOS 27 触控和 VoiceOver 自动化通道，相关结果仍待人工执行。
