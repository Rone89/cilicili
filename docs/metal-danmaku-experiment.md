# Metal 弹幕实验

## 开关与范围

我的 → 开发者诊断 → 实验开关 → Metal 弹幕渲染实验。
`LibraryStore.metalDanmakuRendererExperimentEnabled` 默认 false。
仅视频详情页普通文字弹幕使用实验；直播保持 DanmakuKit。
Metal 不可用或 pipeline 创建失败时使用原 Renderer。

两种模式共享 DanmakuService、DanmakuItem、详情页时间窗、播放器时钟、
DanmakuSettings 和 DanmakuRenderPolicy。切换只替换 host 中的一个子 view，
不重新请求弹幕，不修改 AVPlayer。关闭时保留 DanmakuKit 的 cell、动画、
表情图片和原轨道逻辑。

DanmakuKit 的轨道依赖内部 animated cell，没有可独立使用的公开 scheduler。
实验因此有一个小型几何调度适配器：CPU 负责入场、过期、轨道、防追尾，
GPU 负责 `startX - velocity * (mediaTime - startTime)` 和 glyph quad 绘制。
这是实现差异，不能假设两套 Renderer 在默认密度下每一条 admission 都一致。
普通播放保留保守密度/热状态规则，只有 DEBUG 压力 fixture 可覆盖数量。

## 绘制与资源

- 透明 MTKView；不接受交互；随视频覆盖层尺寸和控件避让区域变化。
- CoreText 对文本 shaping，使用每个 run 的实际 fallback 字体和 glyph。
- glyph 以字体、字号、字重/variation、glyph ID、Retina scale 缓存。
- R8 bitmap atlas，最多四张 1024×1024 页面，默认最多 4 MiB texture 像素。
  只在 miss 时栅格化单 glyph，不生成整条弹幕 bitmap。
- Atlas 满时保留现有 slot，拒绝无法完整绘制的新文本；诊断计数可见。
  内存警告和 teardown 清理 atlas / layout / instance 引用。
- Shader 采样 glyph 周围像素生成黑描边，使用预乘 alpha 混合。
- 每个非空 atlas 页一批 instanced draw，最多四次；空场景只 clear。
- 三份 `.storageModeShared` instance buffer，容量不足时才扩容。
  instance 只在入场/退出/重建时修改，时间通过小型 uniform 更新。
  GPU 未释放 slot 时跳过本次绘制，不在 UI 线程等待 GPU。
  command buffer 持有在途资源，释放页面不会改写旧 instance 的 bytes。

暂停停止连续绘制；恢复与倍速重新锚定单调时钟和视频时间。
seek 使用播放器时钟重新构造当前时间窗，位置不累计历史位移。
布局过渡期间隐藏并暂停；结束后按当前时间重建。
App 不活跃时停止 GPU draw；回前台用最近播放器时间重新同步。

## 限制

图片表情在实验中保留文字 token；彩色 emoji 不保证原彩色外观。
不支持高级/定位/特效弹幕，不新增点击或单条暂停。
目前普通弹幕覆盖层本来就关闭用户交互。
Entry 保留 CPU 时间相关 bounding box，可供未来 hit testing 使用。
Bitmap 适用于当前字号；未来是否采用 SDF 需根据 atlas miss、内存和
缩放质量测量决定，不能由少量 draw call 推断能耗更低。

## 诊断与 A/B

我的 → 播放设置 → 弹幕诊断：开始采集，返回视频播放，再停止并复制。
DEBUG 下可查看活跃数、glyph、draw call、atlas、估算回调 FPS、CPU 准备时间、
GPU command 时间及跳帧/回调间隔。
回调 FPS 不等于屏幕呈现 FPS；GPU command 时间也不等于整机 GPU 占用。
暂停/背景的长间隔不应当作显示掉帧。CPU 指标只覆盖 draw callback 的准备与提交，
不覆盖 configuration 更新或 draw 外的首次 glyph shaping；整体 CPU 成本需 Instruments。
每种模式分开重新开始采集。

DEBUG 本地密度与同步测试使用自产文字，不联网、不含版权媒体。
选择 10/50/100/300/600 条；同一时间和密度切换 Renderer。
分别测试暂停、倍速、前后 seek、连续 seek、旋转、退出再进入和重建。
压力 fixture 开启 overlap 以便真实容纳数百条；不要把它当作正常防碰撞行为。

真机 A/B 固定设备、视频、字体、透明度、显示区域、密度、网络和温度。
先记录 cold glyph 缓存，再记录 warm steady state，每种至少三轮。
用 Time Profiler 测 CPU，Metal System Trace / GPU capture 测提交和执行，
Animation Hitches 测呈现，Allocations / Memory Gauge 测退出后的资源回落，
Energy Log 测能耗。模拟器测试不提供真实 iPhone 功耗数据。

## 构建

项目最低部署版本保持现有 iOS 26.1；没有新增超出 iOS 26 的 API。
shader 使用 Xcode 的官方 Metal Toolchain 编译。
本机目前仅找到 Xcode 27.0/27.1，Xcode 26 验证受阻，不能以辅助编译代替。

## 本轮验证

- Xcode 27.0 辅助 Debug / iOS 27.0 iPhone Air Simulator。
- 186 项回归 PASS / 0 FAIL / 0 SKIP，包含播放器、HLS、SIDX、Range、弹幕数据和渲染。
- 最后字体桥接修正后，27 项定向测试再次 PASS / 0 FAIL / 0 SKIP。
- 21 项新增测试覆盖 glyph 复用/容量/字体/行序/边框、轨道/追尾/重复/seek、
  默认开关/切换/透明/实际 MTKView 提交/暂停恢复/十次创建销毁。
- 实际 GPU 离屏测试：10/50/100/300/600 条在自产文字 fixture 下均为一页、一次 draw；
  相同时间像素一致，时间推进像素变化，背景存在透明区域。
- 尺寸/过渡测试覆盖 portrait/landscape 几何变更；真实视频全屏、切集、
  前后台及长期内存回落仍需真机回归。
- 没有测量真机 CPU/GPU 使用率、屏幕呈现 FPS、进程内存或 Energy Impact；
  模拟器测试不能据此证明性能/功耗收益。

结果包（临时目录）：`/tmp/cilicili-metal-regression2.xcresult`、
`/tmp/cilicili-metal-final-focused.xcresult`。
辅助命令统一使用：

```sh
DEVELOPER_DIR=/Users/rayc/Desktop/Xcode-beta.app/Contents/Developer \
xcodebuild -project bili.xcodeproj -scheme bili -configuration Debug \
  -destination 'platform=iOS Simulator,id=6B297CE5-604E-48E4-893D-1B203ECB6679' \
  -derivedDataPath /tmp/cilicili-metal-danmaku-derived \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:biliTests/DanmakuGlyphAtlasTests \
  -only-testing:biliTests/MetalDanmakuTimelineTests \
  -only-testing:biliTests/MetalDanmakuIntegrationTests test
```

Release 真机目标的未签名构建也通过（Xcode 27.0；没有安装到 iPhone）：

```sh
DEVELOPER_DIR=/Users/rayc/Desktop/Xcode-beta.app/Contents/Developer \
xcodebuild -project bili.xcodeproj -scheme bili -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/cilicili-metal-release-derived \
  -clonedSourcePackagesDirPath /tmp/cilicili-metal-danmaku-derived/SourcePackages \
  CODE_SIGNING_ALLOWED=NO build
```

Xcode 26 validation: **BLOCKED — installation not found**。
本次未新增第三方依赖、私有 API 或播放器策略修改。
