# 本地开发、真机与 GitHub 分工

用户于 2026-11-02 确认以下工作方式：

- Mac Codex：修改代码、运行自动测试、分析日志和真机报告。
- Xcode + iPhone：本地构建后直接安装 `.app`，处理闪退、播放、横竖屏和设备日志；日常迭代不等待云端构建或下载 IPA。
- GitHub：保存提交、备份进度；重要版本执行完整云端回归。已有云端任务可继续，但不阻塞本地排查。未经授权不合并 PR。

## 执行约束

继续遵守 [构建缓存规则](build-cache.md)，跨工作树使用原仓库 Xcode 主版本共享缓存、串行写入；只使用规定的现有本地模拟器。

本地真机优先直接构建签名 `.app`，然后用 XcodeBuildMCP `install_app_device` / `launch_app_device` 更新和启动。MCP 会话先核实项目、设备和 derivedDataPath。签名参数通过本机命令行／会话覆盖，不把证书、密码、描述文件或设备签名配置提交到 Git，也不为安装永久修改项目 bundle ID、签名身份和发布设置。

命令行构建使用现有 `Scripts/build-cache.py run -- xcodebuild ... build`。指定真机 destination，签名团队、身份、profile 和匹配的 bundle ID 来自已授权本机材料。产品路径为共享缓存下 `Build/Products/<Debug或Release>-iphoneos/bili.app`；性能复验沿用 Release 配置，日常调试按需要选择 Debug。直接安装，无需 archive、导出或下载 IPA。重要分发仍复用既有发布脚本和产物目录。

当前授权描述文件 get-task-allow=false，可签名安装并结合设备／崩溃日志分析；附加 LLDB／断点需要允许调试的开发描述文件。不能仅因装了 Debug 配置就承诺可附加调试器，不擅改 profile 权限。

每轮在 [开发状态](DEVELOPMENT_STATUS.md) 记录源码与分支、测试结论、本地／云端的覆盖范围、安装版本和待验证项。真实设备报告发现问题时，优先可控复现、最小修复、本地回归，再递增 Build 安装真机；不把云端上一版成功认作新版本已验证。
