# Sfiora

[English](README-EN.md)

Sfiora 是面向 Android、iOS、React Native 和 UniApp 的通用 NFC 读写库。它提供前台标签发现、NDEF 读取、写入后的回读验证，以及按应用标记保留或初始化标签内容。

应用决定写什么、如何解释与保存数据。Sfiora 负责 NFC 操作，不绑定登录、身份或其他具体业务。

## 能力与边界

- 读取标签技术信息、可用的标识和 NDEF 内容，保留原始字节及常见记录的解析结果。
- 写入完整 NDEF 消息，支持 Text、URI、MIME 和 External Type 记录。
- 写入成功前立即回读，核对完整消息字节。
- 已有指定 External Type 标记时保留原消息，否则写入并验证新消息。
- 进程内读写互斥，提供取消、超时、状态查询和结构化错误。
- Android 可选择原生无界面核心或附带操作面板；iOS 使用系统 NFC 面板。

## 支持平台与分发

| 平台 | 推荐渠道 | 接入说明 |
| --- | --- | --- |
| Android | [Maven Central](https://central.sonatype.com/artifact/io.github.sandroxy/sfiora) · `io.github.sandroxy:sfiora` | [Android 指南](native/android/README.md)，提供可选操作面板与 AAR 离线镜像 |
| iOS | [Swift Package](https://github.com/sandroxy/sfiora) | [iOS 指南](native/ios/README.md)，通过校验和验证的 XCFramework |
| React Native / Expo | [npm](https://www.npmjs.com/package/@sandrox/sfiora) · `@sandrox/sfiora` | [RN 指南](adapters/react-native/README.md)，随包提供 Android/iOS 原生运行时 |
| UniApp | [DCloud 插件市场](https://ext.dcloud.net.cn/plugin?name=Sandrox-Sfiora) | [UNI 指南](adapters/uniapp/README.md)，经典 uni-app 与 uni-app x Vapor 的 Android/iOS App |

版本历史、校验和与离线制品见 [GitHub Releases](https://github.com/sandroxy/sfiora/releases) 和 [CHANGELOG.md](CHANGELOG.md)。各渠道已上架版本以对应渠道页面为准；最低版本、权限和宿主要求见对应平台指南。UNI 指南同时说明共享 UTS 包与 legacy 原生插件的选择。

## 原生接入

Android 在 Maven Central 添加 `io.github.sandroxy:sfiora:<version>`，将 `<version>` 替换为所选公开版本；需要操作面板时再添加同版本 `sfiora-ui`。完整 Activity 示例、面板接入、参数和错误处理见 [Android 指南](native/android/README.md)。

iOS 在 Xcode 添加 Swift Package `https://github.com/sandroxy/sfiora.git`，选择公开版本并链接 `Sfiora` 产品。权限、签名、读写示例和系统会话状态处理见 [iOS 指南](native/ios/README.md)。

RN 和 UNI 包已包含所需原生运行时，无须再单独添加 Maven 或 Swift Package 依赖。各平台指南包含对应宿主的安装与生命周期要求。

## 读写约定

NFC 操作需要支持 NFC 的真机与合适标签。写入要求标签已支持 NDEF、可写且容量足够；发现标签成功不代表它的 NDEF 内容可读或可写。

| 操作 | 对已有内容的处理 | 成功结果 |
| --- | --- | --- |
| 替换写入 | 覆盖整个 NDEF 消息 | 回读字节一致，`verified: true` |
| 初始化：已有匹配标记 | 保留原消息，不比较或更新标记 payload | `preserved`，未写入 |
| 初始化：没有匹配标记 | 覆盖整个消息，包括原有其他内容 | `initialized`，已写入并验证 |

初始化按应用约定的 External Type 标记匹配。待写入消息必须恰好包含一条匹配标记；读取失败不会被当作空标签。具体记录格式、结果字段和示例见各平台指南。

写入没有事务回滚保证。取消、超时、验证失败或标签移开后，应重新读取确认实际内容。标记也不提供锁定或身份认证；Sfiora 不提供标签格式化、永久锁定、密码修改、门禁卡复制、卡模拟或任意 APDU/私有区写入。

## 会话与错误

同一时间只发起一次读写。成功、失败或取消返回后，仍需等待原生会话释放，再开放下一次操作；RN/UNI 提供 `waitForIdle()` 完成有上限的等待。等待超时不代表原生会话已释放。

生命周期处理、错误码和接入排查见 [Android 指南](native/android/README.md)、[iOS 指南](native/ios/README.md)、[RN 指南](adapters/react-native/README.md) 和 [UNI 指南](adapters/uniapp/README.md)。

## 维护与反馈

本地开发、源码测试、环境要求和构建目录管理见 [DEVELOPMENT.md](DEVELOPMENT.md)；候选制品与发布流程见 [RELEASING.md](RELEASING.md)。反馈问题时请提供版本、平台、宿主形态、操作、错误码和相关原生错误，通过 [Issues](https://github.com/sandroxy/sfiora/issues) 提交；去除私密标签数据。安全问题按 [SECURITY.md](SECURITY.md) 报告。

## 隐私与许可

Sfiora 在设备上读取、处理并返回标签数据，按调用方提供的内容写入标签。它不向作者服务器上传标签内容，不包含广告或统计 SDK，不在宿主设备持久化标签内容。业务校验和后续存储由调用方负责。

采用 [Apache License 2.0](LICENSE)。
