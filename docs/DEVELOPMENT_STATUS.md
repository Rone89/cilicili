# 开发接续状态

更新时间：2026-11-03（Asia/Shanghai）。每轮工作结束后更新本文的完成内容、待办、测试结论、分支和提交号。

## 分支与工作区

- 仓库：https://github.com/Rone89/cilicili
- 当前分支：`codex/coin-401-auto-like-build54`，从 Build 53 诊断提交接续投币／点赞修复；Build 50 分支 `codex/rapid-recovery-and-keyboard-build50`、草稿 PR #65 和原 PR #64 保留，不合并。
- 最初接续基线：`8f7070c9622c6729c7f39a97d8e9be12ab103b60`；Build 51 本轮基线：`317f89b02ccdb81f8cf4dff8afe7e125199720e2`。最新源码备份提交见本文件末尾。
- 接续工作树：`/Users/rayc/Desktop/cilicili-build48`。
- 原工作树 `/Users/rayc/Desktop/ccswift` 留在 `main`（`adf2995`），保留原有 3 个修改文件和未跟踪的 `docs/local-main-update-analysis-2026-10-06.md`。没有 stash、覆盖或混入这些改动。
- [PR #64](https://github.com/Rone89/cilicili/pull/64) 为开放的草稿 PR，未合并。用户已授权下一步整理提交并跑完整 CI；本轮仅推送新的 Build 50 分支并开草稿 PR，不合并。
- 当前开发及手机版本：1.1.2 / Build 57，已原位安装并启动。Build 54 按用户选择投币时自动点赞。用户确认未点赞时 `-401 非法访问`，先点赞再投币成功；用户确认 Build 54 真机投币已正常。Build 52 的暂停边界及三组短验收已收集。不开发评论 IP 显示。

## 已完成

- 阅读 AGENTS.md、build-cache、自动恢复测试及重叠恢复修复文档和 PR #64 说明。
- 检查本地改动后 fetch 远端，在独立工作树检出上述分支，HEAD 与用户给定提交一致。
- 继承 Build 48 已实现的连续 seek 意图保持、旧请求隔离、暂停 seek watchdog 修复与 schema 2 耗时分解；首轮真机 21/21 observed，控制流异常未复现，版本间量化性能收益仍未证实。
- 在 AGENTS.md 引用本文并要求后续每轮更新。
- 已实现 [Build 49 非阻塞音频会话停用](playback-audio-session-build49.md)：把停用系统调用移到工作队列，共享激活入口等待在途停用并重查所有权／引擎代数；pause、后台、导航、stop 和 source 替换使旧请求无效。保留音频释放策略和帧／音画恢复保护。异步停用计时捕获原暂停 ID，报告说明已更新。首轮真机确认同步暂停跨度明显下降，整体恢复速度没有一致提升证据。
- 本轮本地兼容修复（已收纳于 Build 50 本地提交）：`SearchAPIProviding` 显式声明 `nonisolated`，解决 Xcode 27.1 测试编译阻断。Swift 默认隔离规则参考 [SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)。
- Build 49 阶段的本地变更现收纳到 Build 50 提交，最终代码提交号及 CI 结论见本文最新轮次。CI #151 不覆盖这些新改动。
- 2026-11-02 后续报告分析轮：收到并校验 Build 47 / schema 1 真机报告（runID `27A61EBA-0B5F-43B0-8B05-B90A2A63F088`），完成 [基线分析](playback-recovery-build47-device-baseline-2026-11-02.md)。21 次中 20 observed、1 timeout；连续拖动失败时最终目标从 playing 变为 paused，暂停拖动三次均出现约三秒后的同 ID 重复 seek 记录。本轮仅增加分析文档和原始报告本地副本，没有修改代码、重跑构建或测试；分支及 HEAD 不变，文档尚未提交。

## 环境与构建约束

- 当前 Xcode：27.1，`/Applications/Xcode.app/Contents/Developer`。
- 唯一允许的本地测试模拟器：iPhone 18 Pro Max / iOS 27.0，UDID `F0B4287D-8633-4CC1-B7C2-0A37F353FE7C`；检查时关机，由 Xcode 测试流程启动，不创建或切换其他模拟器。
- 跨工作树复用原仓库的 `/Users/rayc/Desktop/ccswift/build/DerivedData/Xcode-27`，通过原仓库 `Scripts/build-cache.py run --` 持锁；不创建任务专属永久缓存。
- 原仓库包装脚本将 cwd 切回原仓库，因此项目和 xcresult 必须使用接续工作树的绝对路径。首次误用相对路径的编译已停止，不计作 Build 48 验证。
- 原则上不修改项目签名、描述文件、bundle ID 或发布设置。2026-11-02 用户另行授权使用桌面 18pm 证书签名并安装到其 iPhone；本轮只重签 CI 产物，不修改项目配置或重新构建。

## 测试结论

- 已核实：[CI #151](https://github.com/Rone89/cilicili/actions/runs/41349593879) 对基线提交成功。
- PR 记录：1209 单元、141 UI、12 交互测试通过；照片素材预检曾超时一次，自动重试通过。此为远端历史结果，不冒充本轮本地结果。
- Build 49 本轮本地：13 项脚本测试全部通过；针对性 62 项全部通过；全量单元 xcresult 核对共 1215，1215 通过、0 失败、0 跳过。使用 Xcode 27.1、规定的 iPhone 18 Pro Max / iOS 27.0，共享 Xcode-27 缓存，串行执行。
- Build 48 接续首轮历史：单元共 1209，1206 通过、1 失败、2 跳过（跳过原因分别为受限网络禁用 parallel range fallback 和 startup hedging）；并非 Build 49 当前结果。
- 本轮重点 UI 共 14（CI 的 12 项交互 + 2 项恢复页面），12 通过、2 失败；恢复页面两项均通过。未重跑完整 141 项 UI。
- 历史 UI 失败已定位：评论用例错误要求英文独立 a/A 键，中文九宫格其实已恢复；搜索取消第 43 行失败是未恢复“大家都在搜”，先前误记为等待键盘消失失败。Build 50 评论用例改用原生 space 键与真实输入断言，已回归通过；搜索触摸日志进一步确认 principal 标题区域外的 Cancel 未命中，已改为自适应原生标题分配宽度并覆盖整行手势排除，独立取消回归通过、最终搜索组回归执行中。
- xcresult 同时记录主线程音频会话调用可能阻塞 UI，以及视图更新期间发布状态的运行时警告；仅记录观察，未据此认定为真机恢复延迟原因。
- 原工作树的已跟踪 diff 和 porcelain 状态均与接续前逐字节一致。
- 本地 Release：使用原仓库持锁包装脚本执行接续工作树 `Scripts/build-release-unsigned-ipa.sh`，成功。核验版本 1.1.1、Build 48、bundle ID `cc.bili`、最低 iOS 26.1，无 embedded.mobileprovision 或 _CodeSignature 文件。
- Build 48 本地验证包历史 SHA-256：`81be5dc5bae80f4858f21d6f2c69468b8a23602cf30102c563da5c3230a0c006`。它包含本地网络协议隔离修复，不等同 CI 的 Build 48；其常规 Release 输出和元数据路径现已由 Build 49 覆盖，不能按该历史校验值读取当前输出。CI 原始 Build 48 仍保留在 `build/ci-build48/`。
- 原样基线在 Xcode 27.1 编译失败：`SearchAPIStub` actor 无法遵循被默认推断为 MainActor 的 `SearchAPIProviding`。已给网络协议显式添加 `nonisolated`，与现有 nonisolated `BiliAPIClient` 和 actor 测试替身一致；未更改播放器。修复后的全量本地单元测试已执行 1209 项：2 项因网络策略主动跳过，1 个用例触发 2 条断言失败，整体退出 65。失败用例 `AVPlayerStartupPathOptimizationExperimentTests/testStartupPackagePrebuildReturnsImmediatelyWhenWarmupWaitIsZero` 首次返回 missing（预期 deferred），433ms（预期 <250ms）；单独复测整个类仍失败，耗时 219ms 已满足门槛，但仍返回 missing。日志明确记录 `mediaWarmupBudget action=skip reason=constrainedNetwork`，生产策略拒绝后台预热；当前用例依赖主机网络环境。本轮不修改预热策略或放宽断言。
- 已收到 Build 47 基线：暂停 5/30/120 秒的 playToFrame 中位数分别 161/137/143ms；nearby/distant seek 恢复 total 中位数分别 1047/1083ms；连续 seek 为 2 observed、1 timeout。observed 不等于性能通过，schema 1 无法分解约 732ms 的额外暂停开销。详细口径、记录关联和限制见基线分析文档。
- 已收到并逐条校验 Build 48 / schema 2 真机报告（runID `CE0673F5-9896-454D-BB4F-E616E715A55A`）：21 observed、0 timeout。连续 seek 三次均最终 seekPlaying、同 ID seekReveal/recovered=true；暂停 seek 三次各一条记录且状态检查通过，未复现旧版约三秒的重复 seek。仅确认本轮未复现，不能外推所有场景。
- 新报告定位：9 次普通暂停命令中位数 635.8ms，同 ID 音频会话停用中位数 630.7ms，逐次占比约 99%；playToFrame 中位数 157ms（105–161ms）。优先调查同步停用音频会话开销及 pause/play 竞态。
- 两轮非严格性能对照：Build 47 为 AV1／华为云，Build 48 为 HEVC／CDN 自动选择且独立应用容器；不能量化宣称版本加速，首次加载、音画输出与冷缓存仍待额外验证。详细结果见 [Build 48 真机分析](playback-recovery-build48-device-analysis-2026-11-02.md)。

## 真机验收与报告采集

1. 核对设备中版本 1.1.1（48）。现有 [CI Release 产物](https://github.com/Rone89/cilicili/actions/runs/41349593879/artifacts/13100862005) 为未签名 IPA，PR 记录 SHA-256：`8d04314741f7dc43fdb914eaa5cfb7e1effac2c7061c7a0f23aa9a803a3a98d4`；已下载并复核该文件的 SHA-256、版本和 Build。
2. 使用至少五分钟的录播，等首帧出现，进入“更多播放设置 → 自动恢复测试 → 开始”。保持前台，正常约十二分钟，自动完成七种情景各三次（21 次）。不需逐项手动计时。
3. 完成后复制／分享最终 JSON；也可从“我的 → 开发者与诊断 → 播放与网络诊断 → 自动恢复测试报告”取回。只保留最新一轮，下一轮前先保存报告。
4. 一并记录机型、系统、网络类型、视频、画质／编码和速度、是否中断，以及可见黑帧、画面冻结或有声无画等观察。保持 Build 47/48 对比条件一致。
5. 收到报告后分别比较 observed、timeout、interrupted 等结果，按情景分析首帧／恢复分布；区分 pause/play/seek 同步命令、pauseHold 和实际恢复耗时，检查 audio-session deactivation 占比、最后目标关联、paused seek 是否发生早期重试。缺失证据不得记为零或通过。

## 本地证据与复跑

工作目录为 `/Users/rayc/Desktop/cilicili-build48`，证据保存在被 Git 忽略的 `build/logs/`：

- `build48-unit-final.log/.xcresult`：原样基线在 Xcode 27.1 的编译失败。
- `build48-unit-compatible.log/.xcresult` 与 `build48-unit-summary.json`：兼容修复后的完整单元结果。
- `build48-startup-retest.log/.xcresult`：启动测试类复测结果。
- `build48-focused-ui.log/.xcresult` 与 `build48-focused-ui-summary.json`：14 项重点 UI 结果。
- `release-unsigned-ipa.log`、`build48-release-wrapper.log`：本地 Release 构建证据。

复跑时继续通过 `/Users/rayc/Desktop/ccswift/Scripts/build-cache.py run -- xcodebuild` 持锁，并使用 `-project /Users/rayc/Desktop/cilicili-build48/bili.xcodeproj -scheme bili -configuration Debug -destination platform=iOS\ Simulator,id=F0B4287D-8633-4CC1-B7C2-0A37F353FE7C -parallel-testing-enabled NO`；单元选择 `-only-testing:biliTests`，UI 选择见 CI 的 interaction-regression 列表及 `VideoDetailFlowUITests` 的两项 `testAutomaticRecoveryTest...` 方法。为每次复跑指定新的绝对 `-resultBundlePath`，不要复用已有 xcresult 路径。

## 待办

- Build 49 全量单元 1215 项、5 项重点播放 UI、Release、签名安装及启动均已验证；首轮真机报告 21 observed，暂停命令中位数 5.1ms，12 次后台停用均成功。下一步补充在途快速操作、后台／导航和音画体验证据。此前 2 项键盘 UI 未复跑，失败仍待独立调查，本轮不声称完整 141 项 UI 已通过。
- 后续修复启动预构建用例对真实网络环境的依赖，使用可控环境验证排队与零等待分支；保持受限网络策略。
- 本地 unsigned Release 构建验证已完成；如后续交付包含本轮源码修复的新真机包，先按发布规范递增 Build，重新走验证，不复用 48 作为新交付。
- Build 47/48/49 首轮报告均已归档分析。Build 49 同步暂停中位数约 5ms、后台停用约 106ms、playToFrame 约 150ms；优先补在途快速暂停／播放和后台／导航证据。维持现有恢复窗口，不把同步命令变短认定为恢复整体加速。
- 如需量化版本性能收益，先统一编码、CDN 和设置后重新采样；当前两轮不能作为严格对照。
- 后续每轮结束更新本文，明确本地新增提交（如有）与尚未提交的文件，不把基线 SHA 当作新改动的提交号。


## 2026-11-02 Build 48 真机安装轮

- 授权范围：用户明确要求使用桌面 `18pm证书` 的签名材料，把 Build 48 安装到其 iPhone。不在文档或配置保存证书密码；匹配身份已在钥匙串可用，本轮无需重新导入。
- 来源：CI #151 / artifact `13100862005`，下载至 `build/ci-build48/`，IPA SHA-256 已核对为 `8d04314741f7dc43fdb914eaa5cfb7e1effac2c7061c7a0f23aa9a803a3a98d4`。使用原 CI 二进制，没有混入本地 `SearchAPIProviding` 兼容修复。
- 设备：已配对并连接的 iPhone 18 Pro Max（设备名 RCe2027），iOS 27.2，机型 iPhone19,7；已确认桌面描述文件包含该设备，且证书身份有效。
- 安装：通过现有 `Scripts/sign-install-unsigned-ipa.sh` 签名和安装成功，`codesign --verify --deep --strict` 通过。描述文件固定 App ID，脚本将重签副本的 bundle ID 设为 `app.bamboo2779.brussels691`，未修改源码项目的 `cc.bili`。
- 安装后设备应用列表已核验：新应用 cilicili 1.1.1 / Build 48；XcodeBuildMCP 已成功启动新应用（PID 68224）；原 `cc.bili` 的 Build 47 仍保留。二者独立容器，旧登录和设置不会自动迁移，真机对比前需手动保持设置一致。
- 签名安装日志：`build/logs/build48-sign-install.log`；签名应用：`build/debug-resigned-install/bili-release-unsigned/bili.app`。
- 本轮没有新建构建、运行自动恢复试验或验证性能；下一步在新 Build 48 中运行自动恢复测试，保存 build=48 / schemaVersion=2 的报告。旧 Build 47 图标仍在，注意选择新应用。
- 分支仍为 `codex/seek-intent-and-paused-watchdog-build48`，HEAD 仍为 `8f7070c9622c6729c7f39a97d8e9be12ab103b60`；本地改动及本文仍未提交，未推送或合并 PR。

## 2026-11-02 Build 48 真机报告分析轮

- 完成：读取并保留原始 schema 2 报告，核对 21 个试验、sampleBuild=48、最终目标 ID 与播放模式、12 次音频会话停用关联和 9 次暂停时间分解；完成 `docs/playback-recovery-build48-device-analysis-2026-11-02.md`。
- 验证结论：本轮 21 observed；连续拖动丢失意图和暂停拖动旧 watchdog 重复 seek 均未复现。尚未确认所有环境下完全消除，observed 不等于音画／性能验收通过。
- 新发现：同步显式暂停开销约 0.63 秒，音频会话停用占约 99%；编码和 CDN 与 Build 47 不同，不能计算版本加速比例。
- 待办：优先调查音频会话停用路径与所有权竞态；保持音画保护，再决定最小修复和新 Build。此前本地测试失败仍保留待办。
- 本轮没有改代码、构建、安装、提交、推送或合并。分支 `codex/seek-intent-and-paused-watchdog-build48`，HEAD `8f7070c9622c6729c7f39a97d8e9be12ab103b60` 不变；分析文档及先前本地改动仍未提交。

## 2026-11-02 Build 49 开发与安装轮

- 完成内容：实现 `PlaybackAudioSession` 共享停用／激活顺序管理；系统停用调用离开主线程，合并在途重复停用，激活等待后校验最新意图、停止状态和播放器所有权。保持同步暂停 AVPlayer、notifyOthersOnDeactivation、后台与导航策略，不改变帧和音画保护。听视频激活入口也纳入等待；异步计时绑定提交时的原暂停 ID。版本 1.1.1 / Build 49。
- 新增验证：4 项共享音频会话竞争／失败测试、1 项真实 AVPlayer 在途停用时后台暂停拒绝旧播放的测试、1 项异步计时不串到新暂停的测试。针对性 62/62、全量单元 1215/1215、重点播放 UI 5/5、脚本测试 13/13 全通过，均 0 失败；全量单元 0 跳过。此前受限网络启动用例本轮通过，但环境依赖仍待改进。此前键盘 UI 两项本轮未复跑。
- 环境：Xcode 27.1，已有 iPhone 18 Pro Max / iOS 27.0，原仓库 Xcode-27 共享缓存和包装脚本串行构建；没有清缓存或创建模拟器。初轮针对性测试结束后诊断收集卡住，仅终止 `simctl diagnose` 子进程，之后 xcodebuild 退出 0；日志及 xcresult 保留。全量单元和 UI 正常退出 0。
- Release：通过现有 `Scripts/build-release-unsigned-ipa.sh` 成功构建。核对 1.1.1（49）、原始 bundle ID `cc.bili`、最低 iOS 26.1，未签名包无描述文件／签名目录。SHA-256：`0b7e0f5c3d5c6533b794a134c7fa9f29266fa38de6e908a13a8ce68708ae4fa8`。
- 产物：`build/release-unsigned-ipa/bili-release-unsigned.ipa` 和 `build-info.json`；元数据明确 sourceDirty、本地源码基线 SHA、相关源码文件 SHA-256、工具链与测试结论。这是本地 Build 49，未运行新的远端 CI，不冒充 CI 产物。
- 安装与启动：沿用用户授权的桌面 18pm 签名材料和现有脚本，签名校验通过，覆盖更新 `app.bamboo2779.brussels691`，没有执行卸载或清容器。设备应用列表已核对 1.1.1 / Build 49；已成功启动（PID 68636）。设备为同一 iPhone 18 Pro Max / iOS 27.2。
- 证据：`build/logs/build49-audio-focused.*`、`build49-unit.*`、`build49-playback-ui.*` 及各 summary.json；`build49-release-wrapper.log`、`release-unsigned-ipa.log`、`build49-sign-install.log`、`build49-device-apps-after.log`。原 main 工作区 diff 再次与接续前逐字节一致。
- 待办／真机结论：请在新 Build 49 运行自动恢复测试。比较 pauseCommandMilliseconds、后台 audioDeactivationMs 和 playToFrame；快速暂停／播放及切后台要确认旧请求不误恢复。系统后台调用仍可能约 0.63 秒，不能把它与暂停命令相加或只因暂停命令变短就宣称恢复加速。匹配 Build 48 的编码、CDN 和画质条件；目前没有 Build 49 真机性能报告。
- 分支仍为 `codex/seek-intent-and-paused-watchdog-build48`，Git HEAD 仍为 `8f7070c9622c6729c7f39a97d8e9be12ab103b60`；本轮改动及先前文档／兼容修复均未提交。未推送或合并 PR。

## 2026-11-02 Build 49 真机报告分析轮

- 完成：解析并保存 runID `C2750928-9B1B-4799-8DFB-724EB93472B7` 的 Build 49 / schema 2 原报告，核对全部 21 个试验及 12 个停用事件的 ID、成功标记、普通暂停跨度和连续最后目标。见 [Build 49 真机分析](playback-recovery-build49-device-analysis-2026-11-02.md)。
- 验证结论：21 observed、0 timeout；同步暂停命令中位数从 635.8ms 降到 5.1ms（4.3–7.6ms），后台停用中位数 106.0ms 且 12 次均成功。playToFrame 为 96–152ms、中位数 150ms；连续拖动和暂停拖动旧异常未复现。
- 限制：两轮 CDN 选择不同，暂停恢复分组有快有慢，不能宣传视频加载或恢复整体加速约 99%。本轮普通暂停至少五秒、pausedSeek hold 约两秒，停用均早已完成，不覆盖在途快速连点或切后台竞争。继续保留音画和帧保护。
- 待办：保留 Build 49，补快速操作及后台／导航／音频中断的真机证据；随后处理测试环境依赖、键盘 UI 和提交整理。无需因本轮正常采样而改恢复窗口。
- 本轮只更新分析和开发记录，没有代码改动、构建、测试、安装、提交或推送。分支 `codex/seek-intent-and-paused-watchdog-build48`，HEAD `8f7070c9622c6729c7f39a97d8e9be12ab103b60` 不变，先前源码和文档改动仍未提交。

## 2026-11-02 Build 50 快速操作与 UI 回归轮

- 分支：`codex/rapid-recovery-and-keyboard-build50`；已提交 `04c89ab5c5c8d81bca34ec99b5325a6d55594b26`，收纳 Build 49 非阻塞停用、快速操作 30 次／schema 3、兼容修复和前几轮文档。随后补充搜索工具栏命中区域修复；最终发布提交以远端草稿 PR 为准，原 PR #64 不合并。
- 完成：新增立即暂停／播放、20ms 连续切换后播放／暂停三种情景；记录命令时间线和在途停用证据，最后播放必须匹配最终 play ID，最终暂停等待停用结束并持续观察一秒。缺少竞争证据标为 missingEvidence，旧报告仍兼容。
- 已验证：首轮全量单元 1220/1220、脚本 13/13；20ms 最终间隔随后通过重点单元 31/31。评论原生输入法测试通过；14 项重点 UI 首轮 13/14，剩余搜索取消在工具栏布局修复后独立回归通过。最终搜索全组＋评论回归执行中，完整 CI 和 Release 尚待执行完成。
- 原因与修复：导航栏 principal 标题会绘制到原生点击边界之外，触摸命中导航容器；保留 principal 搜索行，idealWidth/maxWidth 接受原生较小宽度，并将行外点击排除范围包含 Cancel。尝试 topBarLeading 虽能取消，但整组回归发现挤压筛选和我的页，已弃用。评论旧测试要求英文 a/A，现用 native space 键和真实追加输入断言，产品输入法不变。
- 待办：完成最终搜索回归、发布新分支草稿 PR 并跑完整 CI、下载并核验 Build 50 未签名产物、沿用授权证书原位更新 iPhone，再收集 build=50/schema=3/plannedTrialCount=30 报告。Build 50 真机性能、实际音画、后台／导航／耳机与音频中断仍待验证。
- Git HTTPS 推送缺少本机凭据，改用已认证 GitHub 连接器创建同内容 Git tree/commit 并快进新分支；不改动原工作树及其凭据配置，不使用强推。

- 发布补充：草稿 [PR #65](https://github.com/Rone89/cilicili/pull/65) 已创建，首个远端提交 `ebff3689efb31b9ffd50fc98ac154967462846af`，CI #152 正在执行。随后发现搜索 leading 布局导致其他场景回归，改回 principal 并采用自适应宽度，待最终提交与完整 CI 重新确认；不可使用 #152 的 Release 交付最终源码。
- 本机 github.com Git 传输连续连接失败；api.github.com 可用。通过公开 Git commit API 元数据重建对象、逐字节 SHA-1 核验得到远端相同 commit，本地分支已对齐 `ebff3689`；原两次本地提交保存在 `codex/build50-local-backup`。没有修改全局网络／Git 配置。

- 最终源码：`317f89b02ccdb81f8cf4dff8afe7e125199720e2`，本地与远端 tree 一致；CI [#153](https://github.com/Rone89/cilicili/actions/runs/41449548952) 已实际开始，#152 已自动取消。原本地补充提交保存在 `codex/build50-width-local-backup`。
- 最终本地搜索全组 13/13 通过、0 跳过（`build/logs/build50-search-fitting.log/.xcresult` 和 summary.json），含取消、滚动、反复提交、详情返回、筛选、行外点击、我的页及无按钮时宽度回收。评论原生键盘在此前最终组 1/1 通过；该组的其他搜索失败对应已撤回的 leading 布局，不能合并算成最终失败或隐藏历史。原 main 已跟踪 diff 再次逐字节核对未改变。
- 设备 RCe2027 / iOS 27.2 当前连接，签名安装仍待最终 CI 产物。此后本状态文档的更新为本地验收记录，不改变已提交源码或声称最终 CI 已完成。

- CI #153 阶段结果：Release 成功；单元 1220 个唯一用例最终全部通过、0 跳过。`DeterministicAVPlayerTransportTests/testGeneratedDASHSourcePlaysThroughLocalHLSBridge` 首轮等待 AVPlayer item ready 超时，产生两条断言失败，Xcode 自动第二次迭代于 9.706 秒通过；合计 1221 次迭代，不误写成 1221 个独立用例或首轮全绿。首次超时原因尚未确定，不能直接归因于播放器生产逻辑或宣称仅环境问题。日志已保留 `build/ci-build50/verification/unit-log/bili-tests.log`。
- CI artifact `13144841508` 下载与 ZIP digest 核验成功；未签名 IPA 为 1.1.1（50）、`cc.bili`、最低 iOS 26.1，无签名／描述文件。IPA SHA-256：`9f1ac9e04da8ac45a47c23b409fa9d8684ca02f171fbdb4406ba9a56154d2cde`。构建记录的合成 PR commit `88679c3f8bd7d6e2985fd91e49a013fb117f4bca` tree 与源码提交 `317f89b` 的 `7cdff79652d22f4c8a69ffd7d049c29fd9be915f` 完全一致；GitHub 的测试合成提交不代表 PR 已合并。
- 产物与机器可读校验位于 `build/ci-build50/`、`verification/validation.json`（Git 忽略）。UI 分片、交互、签名安装和 Build 50 真机报告仍待完成。

- Build 50 真机交付：沿用用户授权桌面签名材料和既有脚本，签名校验成功，原位覆盖更新 `app.bamboo2779.brussels691`，未卸载或清容器。设备列表核验 1.1.1（50），成功启动 PID 69451。签名日志 `build/logs/build50-sign-install.log`，设备证据 `build50-device-apps-after.json`。本次在单元、Release、本地重点 UI 通过后先行安装以便采样；远端完整 UI 仍在运行，不能据此写成全部 CI 已绿。待用户运行新版 30 次／schema 3 报告，Build 50 真机性能尚未验证。

- CI #153 交互组 12/12 通过、0 跳过、无失败后重试，已核对逐用例日志，包含搜索取消与评论原生键盘两项旧失败用例。4 个完整 UI 分片仍在运行。
- CI 的 swift-format 为既有非阻断检查；日志包含格式规则提示，不能把 job success 等同于源码格式完全无提示。本轮未扩大范围重排历史源码。

- CI #153 首轮最终 6/7 jobs 成功：完整 UI 为 140/141 最终通过，搜索组 13/13 全通过。唯一最终失败 `CommentActionFlowUITests/testReplyActionOpensComposer` 在第 15 行 `app.launch()` 阶段两次失败（Xcode 启动超时、target pid 0 无后台断言），回复操作尚未执行；不能把已安装或搜索通过当作完整 CI 已通过。
- 另有 `AccountLibraryManagementUITests/testCommentDraftReturnsAfterHostRecreationWithoutCrossingContentTargets` 首轮 AX focused-app 属性查询超时、重试通过；RootTabScroll 的 minimized／Reduce Motion 两项首轮超时后重试通过。三份其他 UI 分片分别 36/35/35 全通过。
- 已请求仅重跑 ui-4（CI #153 attempt 2，job `125318440221`），其余成功结果保留，源码仍为 `317f89b`。同一回复用例本地独立复测 1/1 通过（`build/logs/build50-reply-launch-check.*`），Xcode 27.1／规定 iOS 27.0 模拟器／共享缓存，未改代码或放宽断言。首次失败日志保留 `build/ci-build50/verification/ui4-attempt1-log/bili-tests.log`，远端完整收尾仍待重跑结果。

## 2026-11-02 Build 50 报告与本地 Build 51 轮

- 用户新分工已写入 `docs/local-device-development.md` 并由 AGENTS 引用：Mac 修改／测试／日志分析，Xcode+iPhone 本地构建直接安装，GitHub 保存提交／备份并在重要版本云端回归。已有 Build 50 云端重跑继续，但不阻塞本地开发，不为 Build 51 日常迭代再跑整轮云端。
- 分支已从 `317f89b` 切为 `codex/stale-player-observation-build51`，HEAD 暂仍 `317f89b02ccdb81f8cf4dff8afe7e125199720e2`，本轮源码与文档尚未提交。开发版本 1.1.1（51），手机目前仍为 Build 50。
- 收到 Build 50 schema 3 原报告：30 次／29 observed／1 failed，最后一次 rapidTogglePaused keptPaused=false。15 条快速 play 均有 pending 在途证据，23 条音频停用均成功；前 21 个既有情景通过。详细校验、时序和性能口径见 `docs/playback-recovery-build50-device-analysis-2026-11-02.md`。
- 可控复现：真实 AVPlayer 同一 MainActor 内 play→pause，实际 rate=0 但旧 KVO 仍发布 playing 并恢复意图；新增测试在旧代码稳定失败。仅重读 timeControlStatus 仍失败，补充实际正速率校验后独立回归通过。完整本地单元正在执行；补充暂停失败时 isPlaying／wantsPlayback／pending 独立字段，不放宽失败条件或修改音画保护。
- 待办：完成 Build 51 本地单元、直接签名构建 `.app`、原位安装启动、提交备份，再采集新版真机报告。Build 50 原报告不能证明实际出声或唯一根因，Build 51 真机效果尚待验收。

- Build 51 验证与安装已完成：全量本地单元 1222/1222、0 失败、0 跳过；新 KVO 回归由旧代码两个断言失败变为独立及全量通过，新增意图错误／实际播放独立诊断回归通过。最终源码只做观察值刷新与当前 rate>0 核验，没有新增延时、恢复窗口或放宽失败条件。
- 使用 XcodeBuildMCP 和原共享 Xcode-27 缓存串行完成本地签名 Debug（40.3 秒）及 Release（110.2 秒）构建，签名参数仅为命令行覆盖。实际安装 Release 以保持与旧采样配置接近。直接安装 `.app`，没有制作／下载 IPA，没有改项目 bundle ID 或签名发布设置。
- 设备核验 1.1.1（51）／`app.bamboo2779.brussels691`，原位更新成功、启动 PID 69933。应用可执行文件 SHA-256 `838bf878379a664fe5eb35b885261c6e6afc0e91fc97ba008dea891a19218c4c`，签名深度校验通过。`build/logs/build51-device-build-info.json` 记录源文件 hash、配置、构建基线和后续备份提交；`build51-device-apps-after.json` 为设备证据。
- 本地测试证据：`build51-stale-kvo-before.*`（确定性失败）、`build51-stale-kvo-after.*`（仅刷新仍失败）、`build51-stale-kvo-rate-check.*`（补充正速率验证后通过）、`build51-unit.*`／`build51-unit-summary.json`（最终 1222 通过）。MCP 设备构建日志在用户 XcodeBuildMCP workspace 日志目录，构建有既存 Swift 隔离等警告，未扩展本轮修复范围。
- 当前授权 profile 的 get-task-allow=false，可签名安装并收集日志；直接 LLDB 断点附加需要允许调试的开发 profile，未擅改权限。
- 原 main 工作区 diff 再次与接续前逐字节一致。Build 50 首轮 UI4 完整日志已归档；其 256MB 可读诊断 ZIP 在下载时超时，`.zip.partial` 不可作为完整证据，完整远端 artifact 为 `13147406557`，首次失败日志不依赖该 ZIP。新分工下日常开发不等待云端；下一步运行 Build 51 的 30 次真机试验，重点复验 rapidTogglePaused 三次及实际声音／画面，另补后台／导航／耳机、中断和横竖屏验收。

- Build 51 源码及本轮报告／工作流文档已提交并备份：`aa562916e76d9a54c14d6805661c158aca6e4fed`，分支 `codex/stale-player-observation-build51`。通过连接器发布 Git tree 并核对与本地一致，GitHub API 原始 commit 元数据重建后 SHA 逐字节相同；本地分支已对齐。设备实际构建时以 `317f89b` 加本轮工作树源码完成，后续备份的三个应用源文件 hash 均与实际构建记录一致，不冒称构建时 HEAD 已是新提交。
- 仅作分支提交备份，没有创建新的 Build 51 PR、启动 Build 51 完整云端 CI、合并或强推。当前收尾记录为随后文档提交，应用源码提交保持上述 `aa562916`；Build 50 既有云端重跑仍待最终结果。后续每轮继续更新本文。

## 2026-11-02 Build 51 真机报告分析轮

- 分支 `codex/stale-player-observation-build51`，本轮开始 HEAD `4040b651948a4628b631ea4d6dbabfcd1e638279`，应用源码仍为 `aa562916e76d9a54c14d6805661c158aca6e4fed`；本轮只归档、校验和写文档，未改播放器、构建、安装或新开云端回归。
- 收到 runID `65833B09-22BE-46EB-BACD-7D0A30D863FA` 的 Build 51 schema 3 报告：30/30 observed，无失败／超时／缺证。ID、情景次数、sampleBuild、checks、六次最终播放帧 ID、15 条 pending play、21 条成功停用、连续 seek 最后目标和 pausedSeek 单条记录均校验通过。
- 已验证：本轮三次 rapidTogglePaused 均 keptPaused=true，Build 50 旧失败未复现。限制：三次最后暂停前 pending 都为 true，未覆盖 Build 50 失败时 pending=false 的停用结束边界；不能认定所有竞态真机验收完成。详见 `docs/playback-recovery-build51-device-analysis-2026-11-02.md`。
- 性能：普通暂停命令中位数 4.66ms、playToFrame 151ms，仍同一量级；立即恢复 347ms、反复切换后播放 266ms，比 Build 50 本轮更慢，后台停用中位数 181ms。工具链和系统状态等未受控，不直接认定版本加速或退化，不缩短恢复保护窗口。
- 待办：优先补“停用完成后，同一主线程周期 play→pause”的可控自动真机场景，明确记录覆盖条件；随后补实际音画、后台／导航、耳机／中断、横竖屏及首次加载。本轮不要求用户再次重复整套旧计划来碰时序，也不新建 Build。
- 云端收尾：CI #153 attempt 2 已 completed/success，ui-4 重跑 35/35、无失败后重试；其余六个成功任务保留，最终 1220 单元、141 UI、12 交互、Release 通过。首轮 launch／AX／RootTabScroll 超时与单元重试仍记录。该结果仅覆盖 Build 50 源码 `317f89b`，不冒充 Build 51 云端验证。
- 原报告与机器可读核验保存于 Git 忽略的 `build/device-reports/build51-65833B09.json`、`build51-analysis.json`；SHA-256 为 `0f86d02f71ddc9236505f162e50e81fe7a8e1e71910c6ac67af0f1535e893f05`。本轮文档随后提交备份，未合并任何 PR。

## 2026-11-02 Build 52 暂停边界短测轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮基线 `037167c4bdae228160f6a481424e116461f0cfa5`。新增停用完成后的同周期 play→pause 情景，完整计划 33 次，新增三次短测入口。详见 [边界短测说明](playback-recovery-pause-boundary-build52.md)。
- 已实现：schema 4 记录计划类型及命令后实际播放／播放意图；只有停用完成、播放正状态和最终暂停保持均有证据才 observed。未知状态／未同步播放标记 missingEvidence，不放宽故障条件。播放器生产逻辑保持 Build 51，不新增延时策略。
- 本地已验证：针对性 34/34、全量单元 1228/1228，均零失败／零跳过。证据 `build/logs/build52-focused.*`、`build52-unit.*` 及 summary.json。重点 UI 首轮 1 通过／2 失败，两个停止／复制用例因列表报告行在屏幕外未找到结果；补充滚动后复跑 3/3、零跳过通过，包含计划数为三次、停止中断和复制成功，未删除或放宽原断言。证据 `build52-recovery-ui.*`（首轮）和 `build52-recovery-ui-scroll.*`（最终）。尚未取得 Build 52 真机报告，不能记为真机通过或性能改善。
- 已直接交付：Xcode 27.1／共享 Xcode-27 缓存串行签名 Release 构建 104.8 秒成功，签名深度核验通过，设备核验 1.1.1（52）、成功启动 PID 70198；原位更新，没有卸载或清容器。签名仅命令行覆盖，没有 IPA 下载／打包或新开完整云端 CI。既有 Swift 隔离等构建警告保留，未扩展范围修复。应用可执行文件 SHA-256 `791aa708dbace6d7c69a87e8b9aa224c0ba1938e8a082a1d865f51a9a332e266`，源码 hash／构建配置见 `build/logs/build52-device-build-info.json`，设备证据 `build52-device-apps-after.json`。
- 下一步：用户跑三次短测并发最终报告，再据缺证／失败字段决定是否还需定向采集。实际音画、首次加载、后台／导航、耳机／系统中断、横竖屏仍待真机验收。

- Build 52 源码及本轮测试／交付文档已提交并备份：`1b77a638628eeef78a61123e51d61125e7f14141`，分支 `codex/pause-boundary-short-test-build52`。GitHub tree 与本地一致（`8dea0d11889df2d94e2f7fb12494b880202ea8ee`），实际设备构建时的四个改动应用文件 hash 与该提交逐一一致；构建时基线为 `037167c` 加未提交源码，没有冒称构建时 HEAD 已是新提交。本记录随后做文档提交，应用源码保持上述提交。
- 原 main diff／porcelain 与接续前快照逐字节一致。仅新分支备份，没有合并／强推、没有创建 Build 52 PR 或发起 Build 52 云端回归。Build 50 CI #153 的成功不作为 Build 52 云端结论。真机目前仅验证安装启动，边界、实际音画及性能仍待用户报告。

## 2026-11-02 Build 52 真机报告分析轮

- 当前分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `daa4d2946b03809b9d157ca7ea0ebf0a4bffbcce`；应用源码仍为 `1b77a638628eeef78a61123e51d61125e7f14141`。本轮只校验、归档及更新文档，未改代码、构建、安装或重跑自动测试。
- 已验证：收到 schema 4／pauseBoundary 报告 `F788D232-E597-4FA5-9CF2-048BFA6833CF`，3/3 observed，零失败／超时／缺证。三次 play 和最后 pause 前 pending 均 false，命令后意图与实际引擎状态 false→true→false，五项 checks 全 true；六次停用均成功且 ID 归属正确。补齐 Build 51 首轮缺少的停用结束边界，旧暂停异常本轮未复现，不外推所有时序。
- 耗时：三次最后暂停命令 0.469／1.068／1.067ms；第二次后台停用 786.7ms 仍保持最终暂停，不能把后台长尾当成同步暂停阻塞。playToTransport 中位数 32ms，本短测没有首帧记录，不能与旧 playToFrame 直接比较或宣称整体加速。
- 详细结论与局限见 [Build 52 真机分析](playback-recovery-build52-device-analysis-2026-11-02.md)。原报告、断言脚本和机器可读分析存于 Git 忽略的 `build/device-reports/`；原始 SHA-256 `4335d3b72f184c3ce4f5a1a027d912d49193d27b587ae635b2dcbca5625ca11a`。
- 待办：保留 Build 52，优先补实际音画、横竖屏、返回重进、后台恢复的短人工验收；首次加载、耳机／系统中断仍待专项采样。出现异常再按动作／时刻取日志，当前没有依据新增性能修复或新 Build。本轮文档随后提交备份，不合并 PR，不新开云端回归。

## 2026-11-02 Build 52 音画／生命周期验收准备轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `b6fe418a74800036296f9ee090fd0e67db0f9988`；应用源码保持 `1b77a638628eeef78a61123e51d61125e7f14141`，手机仍为 Build 52。本轮没有修改应用、递增 Build、安装或开启云端 CI。
- 已验证：使用规定的 iPhone 18 Pro Max／iOS 27.0 模拟器及原共享 Xcode-27 缓存串行执行现有生命周期 UI 用例，3/3、零失败／零跳过，覆盖后台返回、旋转中退出和全屏往返；这只证明 fixture 的 UI 结构／生命周期回归，不等于真机音画通过。证据 `build/logs/build52-lifecycle-ui.log/.xcresult` 和 summary.json。
- 自动取证已实测：直接从连接的 RCe2027 应用容器读取 `PlaybackRecoveryTests/latest.json`，与用户 Build 52／runID `F788D232-E597-4FA5-9CF2-048BFA6833CF` 粘贴报告逐字段一致；无需重新启动 App 或复制粘贴。系统 crash 目录三个 bili 文件均核对为 2026-10-31／Build 43／cc.bili，未将它们当成当前 Build 52 故障。查询未发现新的同名记录，不据此宣称绝无崩溃。
- 操作步骤、取证命令和结果边界写入 [Build 52 短验收指南](playback-build52-device-acceptance.md)。日志仅本地 Git 忽略目录归档；既有内存性能日志仍需用户在“启动链路性能日志”复制，应用持久化恢复报告不包含本轮人工动作记录。
- 待办：用户用当前版本完成播放中／暂停时横竖屏、返回列表重进、后台约十秒再返回，并反馈音画与状态；异常需动作／时刻和性能日志，若闪退则拉取对应新 crash。首次加载、耳机／系统中断继续待专项验证。现有 MCP 没有真机触摸／旋转能力，未为自动化更改签名／调试权限。
- 原 main diff／porcelain 再次与接续前快照一致。本轮只新增验收文档和状态记录，随后提交备份，不合并 PR。

## 2026-11-02 Mac 一键验收脚本轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `756c544d98c98001877b239eef1aaf042d72006d`；手机／应用源码仍是 Build 52／`1b77a638628eeef78a61123e51d61125e7f14141`。用户明确选择 Mac 桌面双击脚本，真机触摸按提示完成；未修改 App、递增 Build 或重新安装。
- 已完成：`Scripts/device-acceptance.py` 及 `.command` 入口自动核验手机应用、留存报告／崩溃基线、持锁跑三项模拟器 UI、引导三组人工操作、按用户选择读取已复制的性能日志，再采集报告和新增同名 crash、保存 summary 并打开结果目录。桌面 `cilicili一键验收.command` 已建立，本机设备 ID 仅放本机入口／环境变量。操作说明已补到短验收指南。
- 结果每轮独立写入 Git 忽略的 `build/device-acceptance/`，不覆盖旧轮；保留错误／部分结果、未执行／未观察项及用户原始反馈。留存恢复报告明确不是人工生命周期验证证据；崩溃核对 bundle／Build，无新增文件不当成无闪退。没有上传任何设备数据。
- 已验证：3 项脚本证据回归通过；zsh 语法、桌面入口 `--help` 通过；真实手机 collect-only 取证通过。脚本端到端非交互执行成功，三项 UI 3/3，报告 runID 与已验证 Build 52 报告一致，人工三项和总结果保持 pending。证据 `build/device-acceptance/20261102-232904-f24zy6fv/`（采集）、`20261102-232932-jml163t7/`（全自动部分）及 `build/logs/oneclick-launcher-help.log`。
- 待验证：用户双击后按提示完成真机音画／横竖屏、返回重进、后台恢复，选择取回性能日志的交互路径也需实际使用确认；没有代填人工正常。脚本本轮验证不等于真机音画通过。首次加载及耳机／系统中断仍待专项采集。
- 原 main 改动核对不变。下一步交付桌面入口，收到 summary／异常日志继续分析；本轮脚本、测试和文档提交备份，不合并 PR，不新开云端 CI。

## 2026-11-02 一键脚本实机使用与反馈轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `44e11d660698cab56a7167d1a5a4a764bf9d75cb`；应用源码／手机版本仍为 `1b77a638628eeef78a61123e51d61125e7f14141`／Build 52，没有改 App、构建或安装。
- 用户实际运行 23:33:09–23:37:19 的 summary 已核验：自动 UI 3/3、零失败／跳过，errors=[]，性能日志取回成功，前后无新增同名 crash。后台填写正常；横竖屏和返回重进填写“确认”，用户随后明确澄清“两项都正常”。三组短验收用户观察均正常，原 requiresReview 来自脚本输入误分类，不是已证实的 App 异常。
- 已修复脚本：明确 1 正常／2 异常选项；“确认”等文字要求澄清，不直接当故障或通过。空白／未知状态保留 pending，只有三项明确正常且无执行错误才记 userReportedNormal。新增回归后共 6/6 通过；不需要用户重新做本轮手机操作。
- 原 summary 保留，另存 `summary-reviewed.json` 和 `analysis.json` 补记澄清；原始 summary SHA-256 `ca1fbf369ea67b7af46c5b8ee0d6c60ad1891058c98b07d32b7cffaee94a2f1d`。详见 [一键验收分析](playback-build52-guided-acceptance-analysis-2026-11-02.md)。留存暂停边界报告 runID 未变，没有冒称是本轮新测量。设备数据仅本地归档。
- 性能线索：本轮期间更新的三条会话 totalFirstFrame 为 552／840／1450ms；后两条有网页回退取流，playURL 506／605ms，prepare 124／411ms。不同视频／编码／缓存，且每组仅一次，不认定整体性能改善或退化。
- 待办：保留 Build 52，下一阶段优先同条件首次加载采样，追踪取流回退与清单准备；耳机／系统中断仍待专项验收。原 main 改动保留，本轮 Mac 脚本和文档提交备份，不合并 PR、不启动云端回归。

## 2026-11-03 未点赞投币 401 调查轮

- 分支 `codex/coin-401-build53`，基线 `3461341a22fe44b060f46d30ed3cf148ed257c35`，原 main 未提交改动继续保留。初查时完整错误文字及同一视频先点赞后的结果尚待回复，随后用户已补充，见下轮记录。
- 已核对代码：未点赞 select_like=0，已点赞为 1，账号 Cookie／CSRF 来自互动用途快照，非幂等投币 POST 默认不自动重试。不能因 401 就擅自附加点赞、重试扣币或认定账号与点赞状态是根因。
- 已完成 Build 53 诊断增强：仅当投币接口业务码 -401 且返回明确人机验证决定时显示对应提示，其他服务端错误保持原样。仅解析 decisions，不记录验证凭据；没有改变请求参数／点赞、投币或重试行为。详情见 [投币调查](video-coin-401-investigation-2026-11-03.md)。
- 本地模拟回归：`coin401-repro.xcresult` 2/2、`coin401-verification.xcresult` 8/8 通过，验证明确验证信息、普通 -401、未点赞状态不变、不会自动重发、原表单及互动可靠性。模拟服务端不等于真实 401 已复现或功能修复。Build 53 全量单元 1230/1230、零失败／跳过；之后只将提示改为先核对投币状态，最终定向回归 8/8 通过。该阶段手机一度未连接，后续安装结果见下轮记录。
- 本地签名 Release 构建成功（125.5 秒），版本 1.1.1／Build 53 与签名深度核验通过；可执行文件 SHA-256 `8f0c4c418ae3b572ac7d4f2c7e55275d5aad552d917309e7327f1758668a2708`，构建记录 `build/logs/build53-device-build-info.json`。没有制作 IPA，既有 Swift 隔离警告仍在。构建完成时 RCe2027 离线，后续已连接并安装，见下轮记录。
- 当时待办：待设备连接后直接安装 Build 53；结合用户完整提示／先点赞结果继续定位。用户随后授权投币时自动点赞，具体实现及验收状态见下轮记录。

## 2026-11-03 投币时自动点赞／Build 54 轮

- 用户补充原提示为 `-401 非法访问`，同一视频先点赞后投币成功，并明确选择投币时自动点赞。先点赞同时改变账户状态与 select_like，不能仅据此断定服务端拒绝根因。
- Build 53 已在设备 RCe2027 上原位安装、启动 PID 74771，并核对版本 1.1.1（53）；实际构建的两个应用文件哈希与源码备份 `06719aab41ed82c56c2c4dbe862d848130b82f8e` 一致。Build 53 仅在响应明确包含验证要求时改进提示，未改变投币行为，其真机投币结果尚未采集。
- 本轮分支 `codex/coin-401-auto-like-build54`：投币 UI 明确显示同时点赞，投币请求统一 `select_like=1`，没有额外点赞 POST 或自动重投。仅服务端确认点赞后更新未点赞的本地状态，并保护已确认的状态不被旧刷新覆盖；服务端未确认时不虚报点赞。
- Build 54 本地针对性回归 10/10、全量单元 1232/1232 均通过，零失败／跳过。投币弹窗 UI 首轮因父级无障碍标识覆盖子按钮标识而未找到入口，按实际“投币”标签修正选择器后复跑 1/1 通过，确认提示与投币按钮可见可操作。证据 `build/logs/build54-coin-focused.*`、`build54-unit.*`、`build54-coin-ui.*`（首轮）、`build54-coin-ui-label.*`（复测）。
- 本地签名 Release 构建成功（279.0 秒），签名和 1.1.1／Build 54 核验通过；可执行文件 SHA-256 `00325a5cfacc4574ef6b76a376606a41faba38a9c2eb6a315c9af76531f22c8e`。设备原位安装、启动 PID 74985，设备应用列表确认 54；未卸载或清容器。构建记录 `build/logs/build54-device-build-info.json` 和设备记录 `build54-device-apps-after.json`，未制作 IPA，既有 Swift 隔离警告仍在。
- 下一步：用户选择一个未点赞、未投币的视频投一枚，确认是否成功及是否同时点赞；若仍为 -401，按是否提示验证继续收集信息。现有测试是模拟服务端或模拟器，真机尚未复测，不能提前认定 401 消失。没有自动向真实视频投币。原 main 未提交改动保留，不合并 PR、不主动发起云端完整回归。
- Build 54 源码及测试已备份：`fcb0fdaa7c59a17b3f3dddac8fbc6ccefe4e7122`，分支 `codex/coin-401-auto-like-build54`；本地与远端 tree 一致，设备实际构建的四个应用文件哈希与该提交逐一一致。构建时本地 HEAD 为 Build 53 的 `78adab7` 加未提交改动，没有冒称构建时已处于新提交。本记录随后单独做文档提交；用户真机投币结果仍待反馈。


## 2026-11-03 Build 55 评论排序控件

- 用户反馈 Build 54 投币已正常，确认为该场景的真机验收结果；不据此推断其他账号或服务端风控场景。
- 视频详情评论排序及初始加载占位改用 SwiftUI 系统分段 Picker，沿用动态评论的控件样式；切换仍通过既有排序加载流程。版本递增至 1.1.1 / Build 55。
- 使用 Xcode 27.1、指定 iPhone 18 Pro Max / iOS 27.0 模拟器及共享 DerivedData，针对性 UI 测试 1/1 通过，验证最热→最新→最热选择；结果 `build/logs/build55-comment-sort-ui.xcresult`。本轮未重跑全量测试或云端 CI。
- 本轮基线及分支：`codex/coin-401-auto-like-build54` / `e63f73bb7fc20a0719311457f359136cbc99e991`。Build 55 本地 Release 签名构建成功，签名和版本校验通过，原位安装并启动（PID 80290）；首次安装因会话残留旧设备编号失败，改用先前验收的设备后成功。评论排序真机体验待用户验收。源码及上述记录已备份到 `f28f34d961b5f98e6902fd9f17f91faec2051f88`；本句以独立文档提交补记。


## 2026-11-03 Build 56 自动恢复测试入口开关

- 开发者与诊断首页增加“显示自动恢复测试入口”开关，默认关闭并持久保存；开启时视频播放设置显示入口，关闭时隐藏。已有报告仍可在播放与网络诊断查看；使用说明同步更新。
- 模拟器（iPhone 18 Pro Max / iOS 27.0）相关回归 4/4 通过，涵盖隐藏、开启后测试页和报告复制；设置页开关、重启后持久化及菜单显示另 1/1 通过。持久化测试首次未进入“我的”（模拟器旧底栏设置影响），二次点击标签未改变系统开关，修正测试底栏及点击坐标后通过；结果分别位于 `build/logs/build56-recovery-ui.xcresult`、`build56-recovery-setting-ui*.xcresult`。未跑全量或云端 CI。
- 共享 Xcode-27 缓存的 Release 签名构建、签名校验及版本 56 校验通过；原位安装 iPhone 并启动，PID 80545，可执行文件 SHA-256 `6ceefe71a35c8fec19503d69566dd05792c3bcaf6e31b74810f2f207f6285b0b`。真机开关体验待验收；Build 55 评论排序真机体验也尚未收到反馈。
- 分支 `codex/coin-401-auto-like-build54`，本轮基线提交 `401f38a96a785c66bc3ab9dc1164e281f3188349`；本轮源码和记录已备份于 `1722f617a047b2053ccafd5f78a7d3cc44b1f736`；备份状态以独立文档提交补记。


## 2026-11-03 版本 1.1.2 / Build 57

- 对比 GitHub 最新正式 Release `v1.1.1`（tag 提交 `adf2995b61ad402f68d923407bd758f08a359bc6`）与当前分支，整理播放恢复与后台播放、收藏／稍后再看管理、评论草稿与显示、搜索和投币等用户可见变更。不能将未证实的整体播放性能改善写成已验证结果。
- 所有 Xcode 配置的 marketing version 升为 1.1.2，build 升为 57。共享缓存 Release 签名构建成功，版本与签名核验通过，原位安装 iPhone 并启动（PID 80682）。此轮仅变更版本元数据，未重跑测试或完整 CI，真机使用体验待验证；没有发布 GitHub Release。
- 分支 `codex/coin-401-auto-like-build54`；本地基线 `ed96771`，此前 Build 56 远端源码备份 `1722f617a047b2053ccafd5f78a7d3cc44b1f736`；因远端拉取连接超时，本地与远端相同文件树的提交 SHA 不同。本轮版本改动及记录已备份于 `dc96b587bedaa76f90d6fdc922f3e6422561cb6b`，备份状态以独立文档提交补记。
