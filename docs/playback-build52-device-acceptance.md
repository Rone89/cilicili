# Build 52 音画与生命周期短验收

本轮保留手机现有 1.1.1（52），源码 `1b77a638628eeef78a61123e51d61125e7f14141`。三次暂停边界已采集成功，以下项目仍需真实设备操作和观察。不要把模拟器 fixture、启动成功或无崩溃文件当成真实音画通过。

## Mac 桌面一键运行

当前 Mac 已建立 `~/Desktop/cilicili一键验收.command`，连接并解锁 iPhone 后双击。它引用本工作树脚本，本机设备 ID 只放在桌面入口／环境变量，不写入仓库。

1. 自动核对手机应用版本，记录取证前崩溃目录和留存恢复报告。
2. 使用规定的现有模拟器及共享缓存，串行跑三项 UI 回归；详细输出保存在 `simulator.log`，失败不算通过。
3. 按提示在手机做三组动作，回 Mac 输入“正常”或异常动作／时刻。直接回车保留待验证，不自动填通过。
4. 可在手机复制性能日志，再在 Mac 输入 c 取回该文本；脚本只在明确选择后读取剪贴板，并校验性能日志标题，其他内容不保留。可回车跳过。
5. 自动拉取最新恢复报告，比较前后崩溃文件清单、复制新增 bili 崩溃并核对版本信息。结束自动打开本轮结果文件夹，把 `summary.json` 发给 Codex，异常时附对应日志。

每轮结果写入独立的 `build/device-acceptance/<时间>-<随机后缀>/`，不覆盖旧轮、不清缓存、不重装 App、不上传。留存恢复报告标明它不测量本轮人工动作；缺失／失败保留错误，空观察保留 pending，无新增崩溃不等于无闪退。Ctrl-C 可中止并保留部分结果。

命令行入口：`python3 Scripts/device-acceptance.py --device <iPhone-UDID>`；`--non-interactive` 跑自动部分并保留人工待验证，`--collect-only` 仅采集，`--no-open` 不打开 Finder。未指定设备时明确报错，避免自动选错手机。桌面入口已配置当前 iPhone，工作树移动后需更新该本机入口。

## 用户操作（约 2–3 分钟）

沿用同一视频、画质、编码和网络，记录当前后台播放设置；无需清缓存或重跑十二分钟计划。

1. 先播放约十秒，确认画面推进、声音正常。播放中进入横屏再回竖屏，重复三次；再在暂停状态切换一次，确认没有自行恢复播放。观察黑屏、冻结、有声无画或声音重叠。
2. 返回列表，再打开同一视频，确认能正常播放、暂停，无双重声音或残留画面。按当前后台播放设置判断离开详情后的声音，勿把允许的后台播放当故障。
3. 播放中回主屏约十秒，再切回 App，确认按设置处理后台播放且回前台后能正常继续；再在主动暂停后做一次，确认不会自行播放。

反馈格式可直接用：`横竖屏：正常/异常；返回重进：正常/异常；后台回来：正常/异常；音画：正常/异常`。异常附动作、约几点几分、是否闪退和当时播放／暂停状态。

操作后在“我的 → 开发者与诊断 → 播放与网络诊断 → 启动链路性能日志”点“复制性能日志”，发回文本。该日志是现有内存性能记录，出现异常后尽量先复制再重启；不要点清空。若闪退导致内存记录丢失，Mac 采集系统崩溃文件。日志无法自动证明可听声音或屏幕呈现。

## Mac 自动取证范围

已实测可通过 `devicectl` 直接读取当前签名应用的持久化恢复报告，不需要重启 App、清理数据或改变签名权限：

```sh
xcrun devicectl device copy from \
  --device 19CB06D3-D96D-5252-87A1-246DF03EFEC4 \
  --domain-type appDataContainer --domain-identifier app.bamboo2779.brussels691 \
  --source 'Library/Application Support/PlaybackRecoveryTests/latest.json' \
  --destination /Users/rayc/Desktop/cilicili-build48/build/device-reports/build52-device-pulled-latest.json \
  --timeout 15
```

每轮拉取后核对 runID、Build、testPlan 和终态，归档时另存 runID 文件，避免将旧报告当成本次人工验收日志。当前直接读取的报告与用户粘贴的 `F788D232-E597-4FA5-9CF2-048BFA6833CF` 逐字段一致。

崩溃取证先列 `systemCrashLogs` 并筛选 bili，再按确定的相对路径复制具体文件。核对 header 的 bundleID、build_version 和 timestamp，禁止只按文件名认定为当前版本。当前三个 bili 崩溃均为 2026-10-31／Build 43／cc.bili，已归档分类，不是 Build 52 的崩溃。此次目录查询没有发现新的同名记录，仍可能存在报告延迟、别名或未生成日志的退出，不能推导从未闪退。

现有 XcodeBuildMCP 的 UI 操作为模拟器能力，没有可用的真机触摸／方向操作工具；当前分发 profile get-task-allow=false。保留现有签名、系统权限及 Build，不通过修改权限绕过限制。现有模拟器用例可补充 UI 结构与生命周期回归，实际音画及真机旋转由用户验收。测试结果见 DEVELOPMENT_STATUS.md。

本轮证据位于 Git 忽略的 `build/logs/build52-lifecycle-ui.*`、`build52-crash-list.json`、`build52-app-support-list.json`、`build52-pull-report.log`，以及 `build/device-reports/build52-device-pulled-latest.json`、`crash-baseline-build52/classification.json`。设备文件仅本地归档，不上传 GitHub。
