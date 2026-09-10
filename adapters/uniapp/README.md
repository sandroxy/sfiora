# Sfiora 通用 NFC 读写

Sfiora 为经典 uni-app 和 uni-app x 的 Android/iOS App 提供 NFC 标签读取、NDEF 消息写入与回读验证，以及按标记保留或初始化。读写内容由应用决定，可使用文本、URI、MIME 或 NFC Forum External Type 记录。

## 兼容范围与版本选择

| 接入方式 | 页面与运行环境 | 最低系统 |
| --- | --- | --- |
| 经典 uni-app legacy | Vue 2 / Vue 3 的 App Vue 页面，原生插件 | Android API 21 / iOS 13 |
| 经典 uni-app UTS | Vue 2 / Vue 3 的 App Vue 页面，uni_modules | Android API 21 / iOS 13 |
| uni-app x | Vapor，uni_modules | Android API 23 / iOS 15 |

使用 HBuilderX 5.24 或更新版本，并满足所用 HBuilderX、宿主框架和打包工具的系统要求。UTS 市场兼容表对 classic/x 使用共同最低声明 Android API 23 / iOS 15；经典 uni-app 的插件原生配置最低为 API 21 / iOS 13。

NFC 操作需要支持 NFC 的真机。本文的 uni-app x 示例面向 Vapor；Android VDOM 的直接 UTS 入口见下方单独说明。不支持 H5、小程序、nvue 或 HarmonyOS，也不能仅靠标准基座或热更新添加原生 NFC 能力。

各渠道已上架的版本以渠道页面为准；离线包和版本历史见 [GitHub Releases](https://github.com/sandroxy/sfiora/releases)。同一个 App 只安装一种 Sfiora 插件形态。

## 安装与导入

### UTS：经典 uni-app 与 uni-app x

通过 DCloud 插件市场导入 `Sandrox-Sfiora`，或者下载对应发行版的 UTS ZIP。将 ZIP 内的文件解压到 `uni_modules/Sandrox-Sfiora`，确认 `package.json` 直接位于该目录中，避免再嵌套一层同名目录。

两种宿主都使用下面的公共 JavaScript SDK：

```js
import * as sfiora from '@/uni_modules/Sandrox-Sfiora/js_sdk/index.js';
```

它提供 Promise 返回值和带字符串错误码的 `SfioraError`。经典 uni-app 和 x Vapor 使用此入口即可，无须自行处理原生回调或 JSON。

Android VDOM 使用直接 UTS 导入：

```uts
import * as sfiora from '@/uni_modules/Sandrox-Sfiora'
```

直接 UTS 方法返回 `Promise<UTSJSONObject>` 等 UTS 类型；错误对象保留 `code`、`message`、`recoverable`、`nativeError`。这是独立的接入路径，不能把本文的 Vapor JavaScript 导入方式照搬到 VDOM，也不据此推定 iOS VDOM 兼容性。

### Legacy：经典 uni-app 原生插件

下载发行版的 legacy ZIP，将其中的 `Sandrox-Sfiora` 目录放入项目的 `nativeplugins`，然后在 `manifest.json` 的 App 原生插件配置中选择这个本地插件。

```js
import * as sfiora from '@/nativeplugins/Sandrox-Sfiora/js_sdk/index.js';
```

下面经典 uni-app 示例只需替换这一行导入，API 与 UTS 版本一致。原生模块名是 `Sfiora`，但业务代码使用公共 SDK，不需要直接调用 `uni.requireNativePlugin`。

## 权限、签名与自定义基座

Android 插件声明 `android.permission.NFC`，并将 NFC 硬件声明为可选，因此无 NFC 的设备也可以安装应用。NFC 没有运行时权限弹框；使用前通过 `getCapabilities()` 检查设备支持和系统 NFC 开关。

iOS 应用需要 NFC 用途说明、`TAG` entitlement，以及包含 **Near Field Communication Tag Reading** 能力的 App ID 和签名描述文件。用途说明应描述实际应用用途。

经典 uni-app 在 `manifest.json` 中合并以下配置，保留已有的其他权限：

```json
{
  "app-plus": {
    "distribute": {
      "ios": {
        "privacyDescription": {
          "NFCReaderUsageDescription": "读取和写入您选择的 NFC 标签。"
        },
        "capabilities": {
          "entitlements": {
            "com.apple.developer.nfc.readersession.formats": ["TAG"]
          }
        }
      }
    }
  }
}
```

uni-app x 在项目根目录的 `Info.plist` 中添加用途说明：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NFCReaderUsageDescription</key>
    <string>读取和写入您选择的 NFC 标签。</string>
</dict>
</plist>
```

在 `nativeResources/ios/UniApp.entitlements` 中添加：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.nfc.readersession.formats</key>
    <array>
        <string>TAG</string>
    </array>
</dict>
</plist>
```

已有这两个文件时合并键值，不要覆盖其他插件的配置。原生资源目录规则见 [DCloud iOS 原生配置](https://doc.dcloud.net.cn/uni-app-x/collocation/app-nativeresource-ios.html)。使用 FeliCa 轮询时，还需在 `Info.plist` 的 `com.apple.developer.nfc.readersession.felica.systemcodes` 中填写应用支持的真实系统码；ISO 7816 AID 配置也由宿主按目标标签提供。

安装插件、修改原生权限或升级插件后，制作包含当前插件的自定义基座，或重新打包完整 App，再选择该基座运行到真机。基座需要匹配 HBuilderX、平台和插件版本。只修改页面布局或调用参数时，可以在同一匹配基座上重新运行页面；原生模块、权限和签名变化需要重新打包。

## 开始读取

先由用户启动操作，再靠近标签；读写期间保持应用前台并稳定贴住标签。每次 `startScan` 只完成一次读取，不是持续事件订阅。

经典 uni-app 可在页面的方法中调用：

```js
import * as sfiora from '@/uni_modules/Sandrox-Sfiora/js_sdk/index.js';

export async function readTag() {
  const capability = await sfiora.getCapabilities();
  if (!capability.supported || !capability.enabled) {
    throw new Error('当前设备不支持 NFC，或 NFC 尚未开启。');
  }
  try {
    return await sfiora.startScan({ mode: 'automatic', timeoutMilliseconds: 30000 });
  } catch (error) {
    if (error instanceof sfiora.SfioraError && error.code === 'USER_CANCELLED') {
      return null;
    }
    throw error;
  }
}
```

uni-app x Vapor 的 `.uvue` 页面可使用下面的 UTS 方法。调用方将返回值绑定到自己的页面，并处理失败结果：

```uts
import * as sfiora from '@/uni_modules/Sandrox-Sfiora/js_sdk/index.js'

async function readTag(): Promise<UTSJSONObject> {
  const capability: UTSJSONObject = await sfiora.getCapabilities()
  const supported = capability['supported'] as boolean | null
  const enabled = capability['enabled'] as boolean | null
  if (supported != true || enabled != true) {
    throw new Error('当前设备不支持 NFC，或 NFC 尚未开启。')
  }
  return await sfiora.startScan({ mode: 'automatic', timeoutMilliseconds: 30000 })
}
```

三种读取模式：

| `mode` | 行为 |
| --- | --- |
| `automatic` | 默认模式；发现标签，并在可用时读取 NDEF |
| `ndef` | 要求 NDEF；iOS 使用系统 NDEF 兼容读取会话，结果可能没有标签 ID |
| `discover` | 只获取标签信息，不主动读取 NDEF |

结果包含 `id`、`technologies`、`ndef` 和 `warnings`。读取文本用 `tag.ndef.records` 中的 `text`，URI 用 `uri`，二进制内容用 `payloadBase64`。经典 uni-app 可用可选链访问；UTS 使用 `UTSJSONObject` 的访问方法或明确的类型转换。

发现标签成功并不代表 NDEF 读取成功，需检查 `ndef.status`、`ndef.readError` 和 `warnings`。无值或读取错误不能被当成业务上的“空标签”。两端可读的技术信息和 ID 可能不同，不能假设每种模式都会返回 ID。

## 替换 NDEF 消息并验证

下面的方法沿用前面的 `sfiora` 导入，从用户点击事件调用，并在调用处处理 Promise 失败：

```js
export async function replaceTag() {
  return await sfiora.writeNdef({
    records: [{ kind: 'text', text: 'Hello from Sfiora', languageCode: 'en' }],
  }, { timeoutMilliseconds: 30000 });
}
```

这是**替换整条 NDEF 消息**，旧记录会被覆盖。标签必须已经支持 NDEF、可写且容量足够。成功结果包含 `verified: true`、`bytesWritten`、`recordCount` 和回读的 `tag`；验证比较完整 NDEF 消息的序列化字节。

写入没有事务回滚保证。写入开始后失去接触、取消或验证失败，标签可能保留旧内容，也可能变成新内容、部分内容或空内容。失败后重新读取，才能判断标签实际状态；不能把“报错”理解成“原内容一定没变”。

### NDEF 记录格式

`records` 必须非空，可包含多条记录。下面四种记录既可单独使用，也可组合成一条消息：

```js
const records = [
  { kind: 'text', text: '你好', languageCode: 'zh-Hans', encoding: 'UTF-8' },
  { kind: 'uri', uri: 'https://example.com' },
  { kind: 'mime', mediaType: 'application/octet-stream', payloadBase64: 'AQID' },
  { kind: 'external', domain: 'example.com', type: 'initialized', payloadBase64: 'AQID' },
];
```

Text 需要 `languageCode`，默认 UTF-8，也支持 UTF-16。语言码属于 NDEF 格式，不是正文；某些工具的原始值会把语言码和正文一起显示，业务应读取解析后的 `text`。网址建议使用带 `https://` 等协议的 URI 记录。

MIME 和 External Type 的 `payloadBase64` 表达原始字节。例如 `AQID` 写入三个字节 `01 02 03`，不是写入四个字符。若要写入一段字符串，先按应用选择的编码转成字节，再转 Base64。各类记录都支持可选的 `identifierBase64`。

## 保留或初始化

```js
export async function initializeTag() {
  const marker = { domain: 'example.com', type: 'initialized' };
  return await sfiora.initializeNdef({
    records: [{
      kind: 'external',
      domain: marker.domain,
      type: marker.type,
      payloadBase64: 'AQID',
    }],
  }, marker, { timeoutMilliseconds: 30000 });
}
```

将 `example.com` 换成应用自己的小写域名和类型约定。待写入消息必须包含**恰好一条**匹配 marker 的 External Type 记录，插件不会自动补标记。

- 已有消息包含相同 domain/type：返回 `action: 'preserved'`，不写入，返回已有的 `tag`；没有 `verified` 和写入字节数字段。标记记录的 payload 不参与匹配，也不会因传入新 payload 而更新。
- 没有匹配标记：替换整条消息并回读验证，返回 `action: 'initialized'` 和 `verified: true`。已有其他内容但没有这个标记的标签也会被覆盖。
- 无法检查现有消息时返回错误，不把读取失败当成空白。未格式化的出厂标签不会由此自动格式化。

这是一种应用约定的保留机制，不会把标签设为只读，也不是密码保护或身份认证。其他写入工具仍然可以覆盖标记；身份校验、授权、加密和业务格式由宿主负责。

在 x Vapor 中，写入和初始化使用相同消息对象，方法返回 `Promise<UTSJSONObject>`。例如将方法声明为 `async function replaceTag(): Promise<UTSJSONObject>`，读取 `action` 时用 `result['action'] as string | null`。

## 取消、页面生命周期与按钮状态

所有平台提供：

| 方法 | 返回值 |
| --- | --- |
| `getCapabilities()` | 设备 NFC 支持、启用情况和能力 |
| `startScan(options?)` | 单次标签快照 |
| `writeNdef(message, options?)` | 已写入并验证的结果 |
| `initializeNdef(message, marker, options?)` | `preserved` 或 `initialized` 结果 |
| `cancelScan()` | `Promise<void>` |
| `cancelWrite()` | `Promise<void>`，也取消初始化 |
| `isScanning()` | `Promise<boolean>` |
| `isWriting()` | `Promise<boolean>` |
| `waitForIdle(options?)` | `Promise<void>`，有上限地等待本桥接实例空闲 |

取消没有进行中的操作不会报错。取消方法完成只代表请求已送达，原始读写 Promise 的失败仍需处理，也不代表系统 NFC 面板已经收起。

页面应同时禁用读取和写入入口，条件是“本地有未完成调用，或 `isScanning()` / `isWriting()` 任一为 true”。iOS 成功结果可能在系统面板收起前返回，因此不能在 `finally` 中直接恢复按钮；继续查询状态，确认两项都为 false 后再恢复。状态查询失败应显示错误，不按 idle 处理。

`await sfiora.waitForIdle({ timeoutMilliseconds: 5000 })` 可统一完成等待，legacy 的 JS SDK、UTS JS SDK 和直接 UTS API 均支持。超时参数为 1–60000 的整数，默认 5000；查询失败原样返回错误，超时返回 `SESSION_CLOSE_TIMEOUT`，即使查询没有回调也会结束等待。它不取消当前操作、不预留下一次会话，也不会在超时后释放原生占用；用户可刷新真实状态后再试。

原生关闭超过 5 秒时可先交付待处理结果，实际关闭前仍保持忙碌。Android 的读取和初始化判断均使用实时 NDEF 内容，当前空消息不回退到发现时缓存。

拥有当前操作的页面在 `onHide` / `onUnload` 中取消操作，并忽略页面离开后的迟到结果。不要让没有发起操作的页面随意取消另一个页面的会话。原生读写在进程内互斥，重复启动会返回忙错误。

## 参数与错误处理

| 读取参数 | 默认值 | 说明 |
| --- | --- | --- |
| `timeoutMilliseconds` | `30000` | `1000`–`60000` 的整数，单位毫秒 |
| `android.presentation` | `managed` | `none` 关闭 Android 读取面板 |
| `android.deepReadEnabled` | `false` | 对支持的标签启用额外只读协议探测 |
| `android.presenceCheckDelayMilliseconds` | `250` | `50`–`5000` 的整数 |
| `ios.pollingTechnologies` | `['iso14443', 'iso15693']` | 非空数组；添加 `iso18092` 需配置 FeliCa 系统码 |
| `messages` | 内置提示语 | 自定义时提供完整的 `NfcScanMessages` |

写入选项只有 `timeoutMilliseconds`（范围和默认值同上）及完整的 `NfcWriteMessages`，不接受读取专用选项。Android 桥接写入使用操作面板，iOS 使用系统 NFC 面板。未知参数、错误类型或不完整的自定义提示语会返回 `INVALID_OPTIONS`。完整字段见包内 `js_sdk/index.d.ts` 和 `contract/types.d.ts`。

错误包含 `code`、`message`、`recoverable` 和可选 `nativeError`。按字符串 `code` 分支，不依赖设备原生错误文案：

| 错误码 | 处理方向 |
| --- | --- |
| `NFC_UNSUPPORTED` / `NFC_DISABLED` | 检查硬件支持或引导开启 NFC |
| `SCAN_BUSY` / `WRITE_BUSY` | 等当前会话释放，避免连续自动重试 |
| `USER_CANCELLED` | 正常结束这次交互 |
| `SESSION_CLOSE_TIMEOUT` | 保留原生状态门控，允许刷新，不能假定会话已关闭 |
| `SCAN_TIMEOUT` / `WRITE_TIMEOUT` / `TAG_LOST` | 调整贴合位置后由用户重试 |
| `UNSUPPORTED_TAG` / `TAG_READ_ONLY` / `NDEF_CAPACITY_EXCEEDED` | 更换合适的可写 NDEF 标签或缩小消息 |
| `READ_FAILED` | 检查读取错误，不能按空标签继续处理 |
| `WRITE_FAILED` / `WRITE_VERIFICATION_FAILED` | 重新读取确认标签现状 |
| `INVALID_OPTIONS` | 修正参数 |
| `INTERNAL_ERROR` | 检查基座、模块加载、页面生命周期及原生错误 |

`recoverable` 只是重试提示，不保证标签未改变；写入期间的取消、超时和丢失标签也遵循前面的写入不确定性说明。

## 常见接入问题

- **提示模块不存在**：核对安装目录、legacy 原生插件勾选、导入路径，以及运行时选择的自定义基座。只更新 JS 不能补入缺失的原生模块。
- **iOS 会话无法开始**：核对用途说明、最终签名中的 `TAG` entitlement、App ID 与描述文件；修改后重打基座或 App。
- **手机打开了系统标签页面**：先启动 Sfiora 操作再贴标签。空闲时的系统 NFC 分发属于宿主和系统行为；应用若需要处理相关 Intent，应在宿主层处理。
- **取消后按钮暂时不可点**：确认正在等待真实会话释放；按钮状态应与原生状态一致。
- **读到技术信息却不能写**：能发现某种技术不等于能写该标签；写入只面向已支持 NDEF 的可写标签。

## 隐私、能力边界与许可

插件无广告、统计或推广 SDK，不向作者服务器上传标签内容，也不替应用持久化业务数据；写入到标签的数据和宿主后续保存的数据由调用方决定。

Sfiora 不提供标签格式化、永久锁定、密码修改、门禁卡复制、卡模拟或任意 APDU/私有区写入。标记与读取出的 ID 不构成身份真实性证明。

[源码与问题反馈](https://github.com/sandroxy/sfiora) · [版本记录](https://github.com/sandroxy/sfiora/blob/main/CHANGELOG.md) · [Apache License 2.0](https://github.com/sandroxy/sfiora/blob/main/LICENSE)

反馈时提供插件版本、HBuilderX 版本、宿主模式、系统与设备、操作和结构化错误；标签私密内容请先去除。
