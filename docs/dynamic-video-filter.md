# 动态页全部/视频切换实验

在「我的 → 开发者与诊断 → 实验开关」开启「动态页全部/视频切换实验」。默认关闭。

开启后，动态页标题替换为顶部居中的原生分段 Picker（全部/视频）。动态 Tab 和从首页进入的隐藏动态页都适用。关闭后恢复动态标题及全部动态，不修改账号或内容屏蔽设置。

Picker 复用首页的顶部滚动隐藏行为：向上滑动内容、滚动偏移超过 18pt 后淡出，回到顶部重新显示。隐藏时同时移除工具栏背景、禁用点击并从 VoiceOver 导航中隐藏，尊重系统减少动态效果设置。

视频使用现有 `/x/polymer/web-dynamic/v1/feed/all` 接口的 `type=video`，沿用动态请求账号认证及 offset 分页。参数来源为 [PiliPlus DynamicsHttp.followDynamic](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/dynamics.dart) 和 [DynamicsTabType](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/models/common/dynamic/dynamics_type.dart)。客户端进一步要求 `DYNAMIC_TYPE_AV`、存在投稿信息且不是转发，排除直播、番剧及非投稿内容。视频模式不展示直播横条。

两个模式保留各自的 ViewModel、已加载条目及分页游标；切换账号时同时清除。视频不读取或写入全部动态的预热与磁盘首页缓存，避免串数据。网络失败保留已加载条目及分页游标；过滤后空页仍可点击加载更多。

验证覆盖：默认关闭及持久化、投稿类型过滤、模式状态隔离、账号状态重置、视频请求参数/分页/缓存隔离、多账号认证、刷新超时后的分页重试。Xcode 27.1 应用及测试目标编译验证；本地指定模拟器未启动，遵循项目不自动启动模拟器的规定，测试执行与真机界面验收尚未完成。
