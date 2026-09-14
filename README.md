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

写入要求标签已支持 NDEF、可写且容量足够。Sfiora 不提供标签格式化、永久锁定、密码修改、门禁卡复制、卡模拟或任意 APDU/私有区写入。读取出的技术名称不等于支持该技术的全部命令。

NFC 读写需要支持 NFC 的真机与合适标签。模拟器可以用于界面和编译开发，不能完成实际 NFC 操作。标签 ID 及可读信息受设备、系统、标签和读取模式影响。

## 平台与分发

| 平台 | 分发与接入 | 最低要求 |
| --- | --- | --- |
| Android | [Maven Central](https://central.sonatype.com/artifact/io.github.sandroxy/sfiora)，`io.github.sandroxy:sfiora`；可选 `sfiora-ui` | API 21 |
| iOS | [Swift Package](https://github.com/sandroxy/sfiora)，产品 `Sfiora` | iOS 13 |
| React Native / Expo | [npm](https://www.npmjs.com/package/@sandrox/sfiora)，`@sandrox/sfiora`；[接入说明](adapters/react-native/README.md) | RN 0.76+，系统要求同时取决于宿主 |
| 经典 uni-app legacy | GitHub Release 的原生插件 ZIP；[接入说明](adapters/uniapp/README.md) | HBuilderX 5.24，Android API 21 / iOS 13 |
| 经典 uni-app UTS | [DCloud 插件市场](https://ext.dcloud.net.cn/plugin?name=Sandrox-Sfiora)，`Sandrox-Sfiora`；[接入说明](adapters/uniapp/README.md) | HBuilderX 5.24，Android API 21 / iOS 13 |
| uni-app x | [同一市场 UTS 包](https://ext.dcloud.net.cn/plugin?name=Sandrox-Sfiora)，Vapor；[接入说明](adapters/uniapp/README.md) | HBuilderX 5.24，Android API 23 / iOS 15 |

各渠道已上架版本以对应渠道页面为准。版本记录见 [CHANGELOG.md](CHANGELOG.md)，离线 AAR、XCFramework、RN 包和 UNI ZIP 见 [GitHub Releases](https://github.com/sandroxy/sfiora/releases)。示例中的 `<version>` 请替换为所选公开版本。

## 原生接入

Android 在 Maven Central 添加 `io.github.sandroxy:sfiora:<version>`，需要操作面板时再添加同版本 `sfiora-ui`。完整 Activity 示例、面板接入、参数和错误处理见 [Android 指南](native/android/README.md)。

iOS 在 Xcode 添加 Swift Package `https://github.com/sandroxy/sfiora.git`，选择公开版本并链接 `Sfiora` 产品。权限、签名、读写示例和系统会话状态处理见 [iOS 指南](native/ios/README.md)。

RN 和 UNI 包已包含所需原生运行时，无须再单独添加 Maven 或 Swift Package 依赖。各平台指南包含对应宿主的安装与生命周期要求。

## 读写结果与保留规则

原生 `NdefRecord.text`、`uri`、`mime`、`external` 对应桥接 API 的四类记录。原生传入 `byte[]` / `Data`；RN/UNI 的二进制字段使用 Base64。Text 的语言码是记录格式的一部分，业务正文取解析后的 `text` / `decodedText`，不直接把原始 payload 当成文本。

读取成功后检查 NDEF 状态和读取错误，再解释业务内容。标签快照中的缺失字段、读取错误、发现成功但没有 NDEF，均不能直接当作“标签是空的”。

| 操作 | 已有内容如何处理 | 成功结果 |
| --- | --- | --- |
| 替换写入 | 覆盖整个 NDEF 消息 | 回读字节一致，`verified` 为 true |
| 初始化且已有匹配标记 | 保留原消息，不比较或更新标记 payload | `preserved`，没有发生写入 |
| 初始化且没有匹配标记 | 覆盖整个消息，即使已有其他内容 | `initialized`，写入并回读验证 |

初始化消息必须包含恰好一条匹配 domain/type 的 External Type 记录，插件不会自动添加标记。示例的 `example.com:initialized` 应替换为应用自己的小写约定。无法检查旧消息时不会按空白处理；初始化也不会格式化出厂标签。

标记是约定式保留，不是物理防二次写入、密码或身份认证。其他工具仍能覆盖标签；身份与权限校验、加密和具体数据协议由应用处理。

任何 NDEF 写入都不提供事务回滚。写入开始后，取消、超时、失去接触或回读失败可能留下已改变、部分或空内容。只有写入并验证成功才报告写入成功；失败后应重新读取确认实际状态。

## 会话、错误与接入排查

应用同一时间只发起一个读写操作。按钮禁用条件应同时覆盖“调用尚未完成”和“原生仍在读写”；iOS 关闭会话期间可能继续忙碌。RN/UNI 用 `isScanning()` / `isWriting()`，原生用对应客户端状态。取消请求返回不等于系统面板已消失，仍需处理原操作结果。RN/UNI 可用 `await waitForIdle()` 等待本桥接实例的空闲状态，默认最多 5 秒；`SESSION_CLOSE_TIMEOUT` 只表示等待超时，不会取消操作或释放资源。超时后继续按真实状态禁用入口，并允许用户刷新。

原生关闭等待超过 5 秒时可先交付待处理结果，但忙碌状态会保留到实际关闭；不能只凭成功或失败回调恢复入口。Android 普通读取与初始化判断均使用实时 NDEF 结果，不以发现时缓存替代当前空消息。

按稳定错误码处理结果，保留原生错误供排查。`recoverable` 只表达可重试性，不保证标签内容未变。原生 API、选项与错误说明见 [Android 指南](native/android/README.md) 和 [iOS 指南](native/ios/README.md)，桥接接口见 [RN 使用说明](adapters/react-native/README.md) 和 [UNI 使用说明](adapters/uniapp/README.md)；共享类型见 [contract/types.ts](contract/types.ts)。

- 模块不存在：确认原生依赖已加入并重新构建 App；Expo Go 和不含插件的标准基座无法运行。
- iOS 无法开始会话：检查用途说明、NFC capability、实际签名 entitlement 和描述文件。
- Android 打开系统标签页面：先开始操作再贴标签；空闲时的 NFC Intent 处理由宿主决定。
- 能读不能写：确认标签支持 NDEF、可写、容量足够，且操作中持续保持接触。
- 取消后仍忙：等待实际状态回到 idle；不要用固定延迟强行恢复入口。

## 维护与反馈

本地开发、源码测试、环境要求和构建目录管理见 [DEVELOPMENT.md](DEVELOPMENT.md)；候选制品与发布流程见 [RELEASING.md](RELEASING.md)。反馈问题时请提供版本、平台、宿主形态、操作、错误码和相关原生错误，通过 [Issues](https://github.com/sandroxy/sfiora/issues) 提交；去除私密标签数据。安全问题按 [SECURITY.md](SECURITY.md) 报告。

## 隐私与许可

Sfiora 不向作者服务器上传标签内容，不包含广告或统计 SDK，不替应用持久化业务数据。标签内容的生成、验证、写入及宿主侧的后续存储由调用方决定。

采用 [Apache License 2.0](LICENSE)。
