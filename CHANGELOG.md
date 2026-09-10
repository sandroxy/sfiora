# Changelog

各渠道的可用版本以对应发布页面为准，离线文件见 [GitHub Releases](https://github.com/sandroxy/sfiora/releases)。

## 1.1.0（未发布）

- RN Android 的模块调用与 Activity 生命周期统一在主线程管理；关闭中的控制器保留真实忙碌状态。
- iOS 自动读取的 NDEF 查询与读取回调核对实际会话，忽略旧会话的迟到回调。
- Android 将连接关闭移到独立线程，等待 I/O 退出及最终关闭后释放占用，并处理过期标签引起的关闭异常。
- Android 深度读取在切换标签技术前完成 NDEF 关闭；切换期间取消或关闭失败时不进入后续探测。
- Android 读取与初始化判断仅使用实时 NDEF 消息，空消息不再回退到发现时缓存。
- 会话关闭异常迟延时，有界交付待处理结果；实际资源释放前仍保持忙碌，不自动重放写入。
- RN、UNI legacy、UTS 和 x 提供 `waitForIdle()`，等待上限为 5 秒（可配置），查询失败或超时不会伪装为空闲。
- 增加关闭阻塞、迟到结果、取消/超时、写后移开标签和 Android 平台 NDEF 编码交叉验证。
- 补充标签技术互斥、iOS 生产读取链路的迟到回调，以及 RN 主队列与宿主生命周期交错的运行测试。

## 1.0.0

- 提供 Android 与 iOS 原生 NFC 核心，以及 React Native、经典 uni-app legacy / UTS 和 uni-app x Vapor 的 Android/iOS 接入。
- 提供单次前台标签发现、NDEF 读取、原始字节与常见记录解析，以及设备 NFC 能力查询。
- 支持 Text、URI、MIME 和 External Type 记录组成的完整 NDEF 消息写入，成功前回读并验证完整消息字节。
- 提供按 External Type 标记保留或初始化：匹配标记时保留原内容，没有标记时替换并验证新消息。
- 提供进程内读写互斥、取消、超时、会话状态和结构化错误。
- 提供可选 Android 原生操作面板、RN / UNI 的 Android 操作面板与 iOS 系统 NFC 会话集成。
- React Native 支持旧架构和 TurboModules，并提供 Expo 配置插件。

写入仅面向已支持 NDEF 的可写标签，不提供格式化、物理防改写、密码修改或身份认证。写入中断或验证失败不保证旧内容保留；保留/初始化的标记属于应用约定。完整接入方式和边界见各平台使用说明。
