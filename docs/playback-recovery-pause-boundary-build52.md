# Build 52 暂停边界短测

## 目的和操作

Build 51 首轮真机报告 30 observed，但最后暂停三次都在音频停用仍在途时发出，没有覆盖 Build 50 失败时的停用已结束边界。Build 52 保留 Build 51 播放器修复，只扩展测试采集，不调整播放、缓冲、音频释放或恢复保护策略。

打开至少五分钟的视频，等首帧出现，进入“更多播放设置 → 自动恢复测试 → 暂停边界短测（3次）”。保持前台，通常约一分钟，准备／停用超时可能延长。结束后复制最终 JSON。新一轮会替换上轮报告，先保存旧报告。

完整计划保留旧情景并新增本情景，合计 33 次；短测仅执行新情景三次，不要求为碰时序再次运行十二分钟的旧计划。自动命令不代替声音、画面、手势及横竖屏人工验收。

## 覆盖与报告

每次准备好视频后，先暂停，等待 `audioDeactivationPending=false`。未知或等待超时标记 missingEvidence，禁止把缺证记为通过。随后同一 MainActor 连续执行 play→pause，中间没有 await，供已排队的旧播放回调在新暂停之后到达；最终等待停用结束并保持暂停一秒。

只有以下证据齐全才记 observed：

- play 和最后 pause 命令开始前 pending 均明确为 false；
- play 返回时观测到 isPlaying=true 且 wantsPlayback=true；
- 最后暂停后停用结束，保持期间实际播放与意图均为 false。

`isPlaying` 使用现有引擎快照，不能据此声称实际出声或屏幕已呈现新帧。播放没有同步进入正播放状态时仍会立即暂停并记录 missingEvidence，不为得到通过结果而插入异步等待或放宽门槛。出现意外实际播放或意图恢复则失败，保留独立故障字段。

Schema 4：`context.testPlan=pauseBoundary/full`，新情景 `deactivatedImmediatePause`；commands 新增可选的 `isPlayingAfterCommand`、`wantsPlaybackAfterCommand`。旧 schema 1/2/3 和不含新状态的命令仍可解码，字段缺失保持 nil。记录的命令时间／事件收到时间与真实恢复耗时分开。

## 验证范围

本地虚拟时钟回归覆盖三次短测、无异步间隔、未知停用、缺少实际播放、最终暂停后的错误播放和等待期间取消；报告回归覆盖旧格式兼容与新字段往返。页面用例覆盖短视频禁用、完整／短测启动停止与复制。实际执行结果见 DEVELOPMENT_STATUS.md，本地通过不等于真机边界已覆盖。
