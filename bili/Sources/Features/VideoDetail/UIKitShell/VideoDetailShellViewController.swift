/// 旧类型名保留给尚未迁移的调用方。
///
/// 详情页生产路径已经使用 `VideoDetailRotationBridgeViewController`；该别名
/// 避免外部测试或扩展在拆分期间因类型名变化而失效。
@available(*, deprecated, renamed: "VideoDetailRotationBridgeViewController")
typealias VideoDetailShellViewController = VideoDetailRotationBridgeViewController
