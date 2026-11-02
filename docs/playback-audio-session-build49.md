# Build 49：显式暂停的非阻塞音频会话停用

## 问题与变更

Build 48 真机报告中，普通显式暂停命令中位数为 635.8ms，同一暂停 ID 的音频会话停用中位数为 630.7ms，逐次约占 99%。原实现先在主线程暂停 AVPlayer，再同步执行 `setActive(false, options: .notifyOthersOnDeactivation)`，状态发布也要等系统调用返回。

Build 49 保留立即暂停 AVPlayer、后台暂停及显式释放会话／通知其他音频应用的策略，把阻塞的停用调用移到工作队列。项目最低 iOS 26.1，继续使用现有 setActive API，以便旧系统及 CI Xcode 26 SDK 构建；没有引入只在 iOS 27 SDK 可用的异步 API。Apple 对 [setActive](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:)) 的说明以及本机 SDK 头文件明确指出该调用为阻塞操作，应避免在不能长时间阻塞的线程使用。

音频会话是进程共享资源，`PlaybackAudioSession` 协调所有原有激活入口：

- 同时最多一个停用调用。停用期间重复暂停合并，不在新播放后追加旧停用任务。
- 新激活等待在途停用完成；失败也会结束等待，不永久卡住播放。
- 等待完成后重新核对引擎代数、停止状态和活跃播放器身份；显式暂停、scrub 暂停、后台、导航、挂起、停止及新 source prepare 使旧激活无效。
- 引擎恢复播放及 KVO/seek 的 beginPlayback 入口在等待期间不能提前启动。真正的 AVPlayer 操作仍在 MainActor；只把阻塞系统停用调用移到后台。
- 听视频的中断结束／媒体服务重置也经过同一入口，避免绕过等待。
- 不改变静默 scrub pause、帧资格检查、音画揭示窗口、缓冲或恢复 deadline。

## 报告口径

仍为 schema 2。pauseCommandMilliseconds 是立即暂停并提交后台停用任务的同步命令跨度；audioDeactivationMs 是后台系统调用本身的耗时，不再是暂停命令的一部分。很快点播放时，播放可能等待在途停用完成，playToFrame 会保留这段实际等待，不能仅凭暂停命令变短宣称恢复速度提升。

异步停用完成时使用提交时捕获的原 manual-pause sampleID；即使期间已经播放或再次暂停，也不能把旧操作记到新暂停 ID。其他情景或取消运行后不应把未取得的记录记作零。重复暂停合并时，不伪造第二条系统操作计时。

## 本地验证

- 初轮针对性 62 项全通过，覆盖后台执行不阻塞 MainActor、停用完成前不激活、最后暂停优先、播放器所有权切换、停用失败、异步计时归属，以及真实 AVPlayer 本地夹具和听视频回归。
- Xcode 初轮在测试通过后卡于模拟器诊断收集；保留测试日志、采样和 xcresult，仅终止其 `simctl diagnose` 子进程，随后 xcodebuild 退出 0 / TEST SUCCEEDED。未中断测试用例或清理缓存。
- 最终 Build 49 全量单元 1215/1215 通过，0 失败、0 跳过；5 项重点播放 UI 通过，0 失败；13 项构建辅助脚本测试通过。均使用 Xcode 27.1、现有 iPhone 18 Pro Max / iOS 27.0 及原仓库共享缓存，串行执行。未重跑完整 141 项 UI，未执行 Xcode 26 CI。
- 先前 Xcode 27.1 网络协议隔离兼容修复一并保留；受限网络下启动用例的历史失败本轮未复现，测试代码仍依赖网络环境；此前两项键盘 UI 未在本轮复跑。

证据：`build/logs/build49-audio-focused.xcresult`、`build49-unit.xcresult`、`build49-playback-ui.xcresult` 及对应 log / summary.json。Release 和安装结果记录在 DEVELOPMENT_STATUS.md。

## 真机验收

版本 1.1.1 / Build 49。先确认暂停立即生效，再快速交替暂停／播放、暂停后切后台或返回，检查没有延迟的旧播放启动、误恢复声音或新播放被旧停用中断。随后运行 21 次自动恢复测试，重点比较 pauseCommandMilliseconds、audioDeactivationMs、playToFrame 和连续 seek 最终目标。

首轮真机报告已收到：21 observed、0 timeout；同步暂停中位数从 Build 48 的 635.8ms 降到 5.1ms，12 次后台停用均成功。恢复帧中位数 150ms，仍与上一轮同一量级，不能把暂停命令变化当作整体恢复加速。两轮 CDN 不完全相同，在途快速切换及音画体验尚需额外真机证据。详见 [Build 49 真机分析](playback-recovery-build49-device-analysis-2026-11-02.md)。
