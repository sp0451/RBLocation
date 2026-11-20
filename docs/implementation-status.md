# M0 实现与验证状态

更新：2026-10-21。此页区分代码、构建和真机证据，后续以实际验收记录更新。

## 已实现

- 用 `get_cli 1.9.1` 创建 GetX Pattern 工程和三个页面模块，接入 `get ^4.7.3`、CLI 路由 part、大写常量、InitialBinding 和页面 Bindings。[生成记录](get-cli-workflow.md)
- 启动初始化、重试、设备前置条件、临时配对交互、手输 WGS84、示例位置选择、连接/设置/停止。
- 常驻 LocationSessionService；页面离开不停止模拟。初始化幂等、停止可打断设置、关闭期间拒绝新意图、错误可重试。
- 原生权威快照按 runtime/generation/sequence 合并，重复/旧事件丢弃，缺口与原生重启重新同步；配对交互按 operationId 关联，取消后旧 PIN 不复活。
- Pigeon 29.0.10 统一生成 Dart、Swift、Kotlin。连接、命令 sent/acknowledged、位置观测及恢复要求分别显示。
- Android：模拟位置授权、位置权限/系统开关检查、GPS/network test providers、持续前台服务、停止通知、资源清理与原生停止屏障。
- iOS：Bonjour 本机 Remote Pairing、Keychain 凭据、外部 LocalDevVPN 隧道、固定 idevice C FFI、DVT set/clear、Core Location 观测、有限时可取消配对。真机/模拟器库和头文件同源构建。[原生证据](../artifacts/ios/VALIDATION.md)

## 构建与自动化验证

| 检查 | 状态与范围 |
| --- | --- |
| Get CLI 创建与页面生成 | 已实际执行，选择 GetX Pattern |
| Flutter 静态检查 | `flutter analyze` 通过，无问题 |
| Flutter 测试 | `flutter test` 全量 27 项通过，覆盖坐标边界、事件排序/重启、停止竞态、配对隔离、关闭资源、路由和小屏 UI |
| 本地桥接包测试 | 3 项通过，覆盖真实 Pigeon 编码往返、attempt 标识、无交互重放与错误/释放 |
| iOS 无签名真机包 | 最终代码 `flutter build ios --no-codesign --debug` 完整构建 Runner.app 通过 |
| iOS 签名与启动 | 2026-10-21 已使用既有开发签名构建、安装到 iPhone 16 Pro / iOS 27.0.1，`flutter run` 真机启动与权限流程通过 |
| iOS Simulator | 本机 Flutter.framework 只有 arm64，默认双架构命令失败；明确指定 arm64 / iOS 27.0 的 Xcode 整包构建通过 |
| Rust / Swift | 固定 Rust 三架构 release 库；取消测试、Swift warnings-as-errors、C ABI 链接、产物校验通过；Swift pairing token 回归通过 |
| Android | Kotlin 编译、7 项原生 JUnit 与 Debug APK 组装通过；普通 flutter run 安装启动通过；SM-G990U2 / Android 12 的上海→北京→停止主路径、Google Maps 蓝点和系统 provider 观测通过。[真机记录](validation/2026-10-20-android-mock-location.md)、[构建记录](validation/android-build.md) |

本机 Simulator 的构建命令如下；`IPHONEOS_DEPLOYMENT_TARGET` 同时覆盖 Flutter 生成的插件目标。Rust Simulator 库本身包含 arm64 与 x86_64，限制来自当前本机 Flutter 引擎缓存。

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES IPHONEOS_DEPLOYMENT_TARGET=27.0 \
  CODE_SIGNING_ALLOWED=NO
```

以上 Simulator 构建记录是在 deployment target 为 27.0 时产生。本次将工程目标降为 26.0 后，设备 Debug 包构建通过且生成的 Runner.app 标注 `MinimumOSVersion` 为 26.0；当前已提交的 Rust XCFramework 对象仍标注 `minos 27.0`，需用 `native/idevice/scripts/build-ios.sh` 重建后才能确认原生静态库也以 26.0 为目标。定位引擎运行时仍要求 iOS 27+。

## 运行与真机验收

根目录 `flutter pub get` 后，通过 `flutter run -d <device-id>` 在明确选择的手机运行。应用不会启动后自动重放位置。签名安装与操作手机由测试人员主动执行。

Android：在开发者选项中将 CLocation 选为模拟位置信息应用，按设备准备页授予定位权限、开启系统定位；通知权限用于停止入口的可见性。连接后选择坐标，主动点击设置，再用独立 App 观测；停止后检查 provider 清理及后续真实样本。

iOS：使用自己的开发签名侧载，确认开发者模式和 Xcode/DDI 设备准备，安装并启用兼容的 LocalDevVPN。在 Wi-Fi 前台首测，通过设备准备页本机配对，再连接设备服务。验证码只用于当前配对，切换系统设置依赖系统有限后台授权。首次设置 A → 独立观测 → 设置 B → 独立观测 → 停止 → 观察恢复；记录模板见 [阶段验收](development-roadmap.md)。

Android 已在 SM-G990U2 / Android 12 通过单点设置 A/B、Google Maps 蓝点观测及停止恢复验证，测试结束已停止模拟。真机发现的模拟应用列表声明缺失已修复；详见 [真机记录](validation/2026-10-20-android-mock-location.md)。

iPhone 16 Pro / iOS 27.0.1 已通过 Mac 直连 `devicectl` 设置上海、北京，微信 8.0.79 的位置选择页随坐标更新；清除后苹果地图与微信页面回到实际区域。CLocation 已签名安装启动并授予观测权限；首次工具检查时尚缺 App 本机配对及 LocalDevVPN 链路。[iPhone 真机记录](validation/2026-10-21-ios-mac-location.md)

随后用户反馈已安装 LocalDevVPN 并测试成功。手机端状态更新为“用户反馈测试成功”；本条反馈后未用工具复测，也未逐项提供目标 App、A/B、停止恢复或后台等场景结果。[手机端用户反馈](validation/2026-10-21-ios-user-feedback.md)

Mac 辅助测试不替代手机端链路验收。CLocation 的 iOS DVT set/clear 实现仍只有发送语义；第三方 App 接受本轮 Mac 模拟，不代表已接受由 CLocation 发出的命令。

## 当前限制

2026-10-21 同机复核：微信 8.0.79 的位置选择页在系统持续返回深圳 mock 坐标时，仍显示实际位置区域；同期 Google Maps 正常显示深圳。已标记为微信兼容性未生效，具体 SDK 过滤/网络定位/缓存路径尚未确定。[微信兼容性记录](validation/2026-10-21-android-wechat-compatibility.md)

用户已将后续替代研究限定为当前三星免 Root。应用内加载与虚拟容器为研究候选，尚未安装、集成或通过微信验证；当前没有确认能直接改变原有官方微信定位的新方案。[替代方案研究](wechat-no-root-feasibility.md)

M0 尚无在线地图、地名搜索、收藏、路线、GPX 或摇杆。iOS 依赖外部本地隧道和设备开发者服务；不保证长期后台、锁屏、蜂窝首连或任意其他 App 接受定位。iOS 当前没有持续心跳，传输丢失在下一次原生命令时识别。停止或关闭后没有新鲜的真实位置样本时，恢复状态保持待确认，断连不当作恢复成功。
