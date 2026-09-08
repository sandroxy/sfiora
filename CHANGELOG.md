# Changelog

各渠道的可用版本以对应发布页面为准，离线文件见 [GitHub Releases](https://github.com/sandroxy/sfiora/releases)。

## 1.0.0

- 提供 Android 与 iOS 原生 NFC 核心，以及 React Native、经典 uni-app legacy / UTS 和 uni-app x Vapor 的 Android/iOS 接入。
- 提供单次前台标签发现、NDEF 读取、原始字节与常见记录解析，以及设备 NFC 能力查询。
- 支持 Text、URI、MIME 和 External Type 记录组成的完整 NDEF 消息写入，成功前回读并验证完整消息字节。
- 提供按 External Type 标记保留或初始化：匹配标记时保留原内容，没有标记时替换并验证新消息。
- 提供进程内读写互斥、取消、超时、会话状态和结构化错误。
- 提供可选 Android 原生操作面板、RN / UNI 的 Android 操作面板与 iOS 系统 NFC 会话集成。
- React Native 支持旧架构和 TurboModules，并提供 Expo 配置插件。

写入仅面向已支持 NDEF 的可写标签，不提供格式化、物理防改写、密码修改或身份认证。写入中断或验证失败不保证旧内容保留；保留/初始化的标记属于应用约定。完整接入方式和边界见各平台使用说明。
