# 三方依赖与接入策略

更新日期：2026-10-20。M0 已接入 Get、Pigeon、本地桥接与固定 idevice；M1/M2 表格仍为候选。构建与真机证据见 [实现状态](implementation-status.md)。架构边界见 [项目架构](architecture.md)，提交要求见 [开发规范](development-standards.md)，阶段验收见 [开发路线](development-roadmap.md)。

## 1. 工程基线与选择原则

当前本机基线为 Flutter 3.44.2 stable / Dart 3.12.2，根工程约束为 `sdk: ^3.12.2`。Android 首期基线为 minSdk 24、compileSdk 36、targetSdk 36、Build Tools 36.1.0；iOS 宿主和插件 deployment target 为 26.0，Rust 构建脚本也已配置为 26.0，但仓库内现有 XCFramework 仍以 27.0 为最低版本，需用固定工具链重建。首测设备仍为 iPhone 16 Pro / iOS 27.0.1。部署目标不代表定位功能已兼容 iOS 26；当前原生定位引擎的本机配对和连接仍受 iOS 27+ 运行时门槛限制。

优先使用 Flutter 官方维护的基础插件，状态管理、依赖注入和路由统一采用用户指定的 **`get: ^4.7.3`**。按功能阶段引入依赖，不先加入整套网络、数据库和代码生成框架。下文最低约束仅列已核实的发布包、包页面、版本列表或 changelog 明文；“未单列”表示本轮核对页面没有找到单独数值，不表示没有约束。最终以选定版本发布包的 `pubspec.yaml`、传递依赖、原生配置和实际构建为准。

包的最低 iOS 版本只说明该包本身的支持范围，不能扩展本项目定位引擎的系统支持声明。Flutter 界面插件也不能替代 iOS 开发者服务或 Android 模拟位置的原生实现。

## 2. 当前已有

| 依赖 | 当前声明 | 用途 | 已核实约束与许可 | 来源 |
| --- | --- | --- | --- | --- |
| `flutter` | Flutter SDK | 基础框架与 Material 组件 | 随 SDK 固定；BSD-3-Clause | [Flutter 源码及许可](https://github.com/flutter/flutter) |
| `flutter_test` | Flutter SDK，开发依赖 | 单元与 Widget 测试 | 随 SDK 固定；BSD-3-Clause | [SDK 测试包](https://github.com/flutter/flutter/tree/master/packages/flutter_test) |
| `flutter_lints` | `^6.0.0`，开发依赖 | 静态规则基线 | Dart ≥3.8；BSD-3-Clause | [6.0.0](https://pub.dev/packages/flutter_lints/versions/6.0.0)、[版本约束](https://pub.dev/packages/flutter_lints/versions) |

## 3. M0：能力查询与单点定位验证

先完成输入坐标、检查能力、连接、设置、停止和观察恢复。此阶段不依赖在线地图或地名搜索。

| 依赖 | 候选版本 / 固定方式 | 职责 | 已核实最低约束 | 许可 / 来源 |
| --- | --- | --- | --- | --- |
| `get` | **`^4.7.3`，已接入，锁定 4.7.3** | `GetxController` + Rx/`Obx` 状态；`Bindings` 依赖注入；`GetMaterialApp`、`GetPage`、命名路由 | 4.7.3 发布包：Dart ≥2.15.0 <4.0.0；Flutter ≥3.13.0；未单列原生系统下限 | MIT；[4.7.3 包说明](https://pub.dev/packages/get/versions/4.7.3)、[官方仓库](https://github.com/jonataslaw/getx) |
| `pigeon` | 开发依赖精确 `29.0.10`，已生成三端通道 | 生成 Dart ↔ Swift/Kotlin 的类型化通道；首期使用 Platform Channels 模式 | Flutter ≥3.41 / Dart ≥3.11；各原生目标需构建验证 | BSD-3-Clause；[说明及兼容要求](https://pub.dev/packages/pigeon)、[29.0.3 起的 SDK 基线](https://pub.dev/packages/pigeon/changelog) |
| 自研 `location_bridge` | 仓库内本地包，随应用版本管理 | 提供稳定能力、配对交互、会话命令、状态事件和错误模型 | 部署目标 iOS 26.0；定位运行时当前要求 iOS 27+，iOS 26 真机能力未验证 | 自有代码；接口见 [架构](architecture.md) |
| `idevice` | 已固定 `e98264c4194e6980173c576ac79a58adce95492b`，附 Aurora MIT 补丁 | iOS Swift 包装层通过 C FFI 接入 Rust 的设备开发者服务 | 上游没有在已核对 README 中给出可直接照搬的本项目系统兼容矩阵；需验证 iOS 27.0.1 | MIT；[作者仓库](https://github.com/jkcoxson/idevice) |
| LocalDevVPN | 外部安装依赖；验收记录安装版本，当前商店页面为 1.3.0 | 为 iOS 原型提供本地网络隧道；不是 Flutter 插件，也不直接修改 GPS | 商店声明 iOS ≥14.0；本项目仍按 iOS 27.0.1 单独验证 | 商店分发的软件，未据此确认源码复用许可；[作者商店页面](https://apps.apple.com/us/app/localdevvpn/id6755608044)、[Locus 接入说明](https://github.com/ChrisMack32/Locus) |

### GetX 使用边界

`get ^4.7.3` 同时承担状态管理、依赖注入和路由，从 M0 开始配置，不再单独引入其他状态库或路由库。应用使用 `GetMaterialApp`，`app/routes/app_pages.dart` 统一登记 `GetPage` 及页面 `Binding`，`app/routes/app_routes.dart` 定义路由常量，通过 `Get.toNamed` 等命名路由 API 导航。具体生命周期规则见 [开发规范](development-standards.md)。

`LocationSessionService extends GetxService` 在 bootstrap / `InitialBinding` 的应用装配阶段只注册一次，并持续持有脱敏原生快照订阅；页面 `GetxController` 由路由 `Binding` 使用 `Get.lazyPut` 创建。离开页面释放 UI 订阅和 workers，原生会话不随页面销毁。常驻服务必须提供显式 `shutdown()`；生产代码不使用 `Get.reset()` 管理会话或停止定位，测试先调用 `shutdown()` 再在 teardown 清理 Get 注册表。路由不得通过 `fenix` 自动重建会话服务。

本轮通过本机已有的 **4.7.3 发布包** `pubspec.yaml` 与 `LICENSE` 核对上述 SDK 约束及 MIT 许可；同时核对 [指定版本页面](https://pub.dev/packages/get/versions/4.7.3)。官方仓库默认分支可能已是 GetX 5 预发布代码，后续查询 API 以锁文件实际解析的 4.x 发布包为准，不能直接套用 5.x API。`^4.7.3` 允许兼容的后续 4.x，实际版本由接入时提交的锁文件固定；当前锁文件已解析为 4.7.3。

### 必需开发工具：Get CLI

项目及新增页面必须使用 **get_cli 1.9.1** 创建，选择 GetX Pattern。CLI 仅用于开发，不进入 App 运行依赖。目录、路由 part、大写常量和 Controller/View/Binding 均沿用生成规范；业务组件补充模块内部 `widgets`，全局服务与数据源按职责扩展。完整命令和本轮创建记录见 [Get CLI 工作流](get-cli-workflow.md)。[官方说明](https://github.com/jonataslaw/get_cli)

Android 插件使用 `kotlinx-coroutines-android:1.11.0` 支持 Pigeon 29 的 suspend API 和主线程消息调度；`junit:junit:4.13.2` 仅为 native 单测依赖。[Coroutines 官方发布记录](https://github.com/Kotlin/kotlinx.coroutines/releases/tag/1.11.0)

`location_bridge` 对外只暴露本项目接口；Pigeon 生成类型留在包内部。Dart、Swift、Kotlin 必须由同一版本 Pigeon、同一份定义一次生成，不混用旧生成文件，也不手改生成代码。Pigeon 官方说明不同生成器版本通信行为未定义，可能导致崩溃；其新 FFI/JNI 模式仍标为实验功能，首期不采用。[Pigeon 版本兼容说明](https://pub.dev/packages/pigeon)

Rust `idevice` 是真正底层能力的一部分，需要固定源码、工具链和构建产物。升级时同时更新 C header、静态库或 XCFramework、Swift 包装层，验证 ABI、内存释放和取消行为；不能仅替换二进制。上游能力存在的证据与本项目实测记录应分别保存。[idevice 项目说明](https://github.com/jkcoxson/idevice)

本机 Flutter 3.44.2 的 iOS 插件接入优先使用 SwiftPM，自研插件把源码置于 `ios/location_bridge/Sources/location_bridge/`，固定的 `IdeviceRuntime.xcframework` 通过包内 binary target 接入。接入三方插件时检查其 SwiftPM 支持；需要 CocoaPods 回退时再核实相应工具链。具体产物路径见 [目录规范](directory-structure.md)。[Flutter 插件 SwiftPM 指南](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors)

## 4. M1：地图与产品基础

M0 在目标手机上通过后再接入地图选点、收藏、设置、诊断和多页面导航。

| 依赖 | 候选版本 | 职责 | 已核实最低约束 | 许可 / 来源 |
| --- | --- | --- | --- | --- |
| `flutter_map` | `^8.3.2` | 地图画布、标记、选点和路线预览 | Dart ≥3.6；Flutter 与系统版本在已核对页面未单列 | BSD-3-Clause；[包说明](https://pub.dev/packages/flutter_map)、[版本约束](https://pub.dev/packages/flutter_map/versions) |
| `latlong2` | `^0.10.1` | 地图适配中的经纬度对象、距离等计算 | Dart ≥3.0；纯 Dart，无单独原生系统下限 | Apache-2.0；[包说明](https://pub.dev/packages/latlong2)、[版本约束](https://pub.dev/packages/latlong2/versions) |
| `shared_preferences` | `^2.5.6` | 非敏感设置与轻量偏好；收藏由 JSON 文件统一管理 | Flutter ≥3.41 / Dart ≥3.11；Android SDK 24+ / iOS 13.0+ | BSD-3-Clause；[支持矩阵与注意点](https://pub.dev/packages/shared_preferences)、[SDK 基线](https://pub.dev/packages/shared_preferences/changelog) |
| `path_provider` | `^2.1.6` | 应用支持目录、缓存目录、脱敏诊断文件路径 | Flutter ≥3.38 / Dart ≥3.10；Android SDK 24+ / iOS 13.0+ | BSD-3-Clause；[支持矩阵](https://pub.dev/packages/path_provider)、[SDK 基线](https://pub.dev/packages/path_provider/changelog) |

`flutter_map 8.3.2` 的发布元数据允许 `latlong2 >=0.9.1 <0.11.0`，因此 `0.10.1` 落在其声明范围内；最终仍需一次依赖求解和地图交互验证。业务领域模型不暴露 `LatLng`，在地图适配边界转换为项目自己的 `Wgs84Coordinate`。[flutter_map 依赖声明](https://pub.dev/packages/flutter_map)

`shared_preferences` 使用较新的 `SharedPreferencesAsync` API，避免 Flutter 与原生同时修改时读到旧缓存。它不保证关键数据持久化，不存配对记录、证书或私钥；这些由 iOS 原生层使用 Keychain 或受文件保护的原生存储管理，敏感材料不穿过 Dart 通道。完整轨迹等大体积文件也不放入 preferences。[插件存储限制](https://pub.dev/packages/shared_preferences)

`path_provider` 只解决文件目录，不提供加密、密钥管理或备份排除。诊断文件设置容量、保留期限和清理策略；配对文件的保护、备份策略由原生安全存储实现。

### 地图服务边界

`flutter_map` 是地图客户端，不随包附赠瓦片服务、地名搜索、逆地理编码、路线规划或全球离线地图。瓦片供应商、URL 模板、坐标系、归属信息和请求配置均由地图适配层集中管理；搜索供应商另行选型。服务不可用时保留经纬度手动输入，不影响 M0 的核心验证。[地图客户端说明](https://pub.dev/packages/flutter_map)

如原型使用 `tile.openstreetmap.org`，必须显示归属信息，设置能识别本 App 的稳定 User-Agent，遵守缓存响应头，不批量预取或制作离线包。需要离线能力时另选明确允许预取和离线使用的服务或自建资源。不要把公共 OSM 瓦片当作无配额保证的生产基础设施。[OSM 瓦片使用政策](https://operations.osmfoundation.org/policies/tiles/)

## 5. M2：路线文件导入与分享

| 依赖 | 本机基线下候选 | 职责 | 已核实最低约束 | 许可 / 来源 |
| --- | --- | --- | --- | --- |
| `xml` | `^7.0.1` | GPX 文件解析与生成；GPX 语义校验仍由项目实现 | 7.0.1：Dart ≥3.11，纯 Dart；最新 stable 7.1.0 要求 Dart ≥3.13，当前 Dart 3.12.2 不选用 | MIT；[7.0.1](https://pub.dev/packages/xml/versions/7.0.1)、[版本与 SDK 列表](https://pub.dev/packages/xml/versions) |
| `file_picker` | `^13.1.0` | 系统文件选择入口 | Dart ≥3.10；iOS ≥14.0；Flutter 与 Android 下限在已核对页面未单列 | MIT；[平台说明](https://pub.dev/packages/file_picker)、[Dart 约束](https://pub.dev/packages/file_picker/versions) |
| `share_plus` | `^13.3.1` | 分享 GPX 或用户选定的脱敏诊断文件 | Flutter ≥3.38.1 / Dart ≥3.10 <4；iOS ≥13.0；Java 17 / Kotlin 2.2.0 / AGP ≥8.12.1 / Gradle ≥8.13；Android minSdk 在该要求列表未单列 | BSD-3-Clause；[要求与使用说明](https://pub.dev/packages/share_plus) |

`xml ^7.0.1` 允许后续 7.x，但当前 Dart SDK 应排除不兼容版本；锁文件记录实际解析版本。升级 Dart 后不要顺带无审查升级 XML，需复测 GPX 解析、坏文件、超大文件与坐标边界。

文件选择后先校验扩展名、实际内容、大小、点数和坐标，再复制到应用受控目录处理；不要假设系统选择器返回的路径永久有效。GPX 导入可用不等于路线回放可用，需独立验证原生引擎支持与生命周期。

`share_plus` 引入的 Android 工具链要求高于仅看 Dart 版本所能判断的范围；到 M2 接入时检查工程 AGP、Gradle 和 Kotlin，而不是为了文档提前升级工程。iPad 分享需要正确的弹窗来源区域；分享缓存文件须按期清理。[分享要求与平台注意点](https://pub.dev/packages/share_plus)

## 6. 首期不默认纳入的依赖

| 依赖或方案 | 当前决策 |
| --- | --- |
| `geolocator` / `location` | 读取定位和观察位置不能完成系统定位改写；原生验证观察器可先随 bridge 实现。后续若有独立读取需求再评估。 |
| `permission_handler` | 首期所需权限和系统设置状态由 Swift/Kotlin 统一管理，避免形成两套权限状态来源。 |
| `flutter_secure_storage` | 配对私钥等留在原生层，避免敏感配对材料经过 Dart；后续有明确 Flutter 侧密钥需求时再评估。 |
| 通用 VPN 插件 | VPN 本身不修改 GPS；LocalDevVPN 是当前研究路线的外部隧道依赖，不能等同于定位引擎。 |
| `dio` | 首期核心定位链路不依赖业务 HTTP API；地图或搜索服务明确后再决定是否需要独立 HTTP 层。 |
| SQLite / Drift / Isar 等数据库 | 小规模收藏先由仓储接口隔离，达到明确的数据量、查询或一致性需求后再选型。 |
| `freezed` / `json_serializable` / `build_runner` | 首期模型规模较小，手写即可；GetX 不需要生成状态代码，Pigeon 是唯一必需的跨语言生成步骤。 |
| AGPL 参考项目代码 | 可以研究能力和行为；直接复用前单独核实代码来源与许可义务，不按 MIT 项目处理。 |

这些是本项目当前范围的工程选择，不表示相关库本身不适合其他场景。

## 7. 版本、许可和构建产物管理

1. 根应用包采用明确版本的 caret 约束，并提交 `pubspec.lock`；CI 使用已审查锁文件，不在构建过程中无条件执行升级。第三方 Dart 库若被业务代码直接 import，即使也是传递依赖，也应显式声明。
2. 仓库内 `location_bridge` 的 Pigeon 开发依赖和锁定的解析结果纳入构建记录；定义变化后同时生成 Dart、Swift、Kotlin，并检查生成文件无遗漏。公开封装接口与生成消息类型分离。
3. Rust 依赖固定 Git commit，提交原生构建工程的 `Cargo.lock`，记录 Rust 工具链、构建参数、目标架构、上游来源、commit、产物 SHA-256 和许可证。header 与静态库必须来自同一源码与构建。
4. 发布时收集全部直接和传递依赖的许可证与必要 NOTICE；MIT、BSD 和 Apache 的标识不能替代保留实际许可文本。外部安装软件与嵌入式源码分别登记。
5. 每次新增或升级依赖，记录用途、替代方案、平台要求变化、引入阶段和验证结果。常规产品插件变更不能自动扩大定位引擎的能力声明。

版本锁定依据：[Dart 应用依赖与 lockfile](https://dart.dev/tools/pub/dependencies)、[Pigeon 跨端版本要求](https://pub.dev/packages/pigeon)、[Cargo.lock 使用指南](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)。

## 8. 接入顺序与完成条件

1. **M0**：按 Get CLI 模块结构组织应用；加入 `get: ^4.7.3` 与 Pigeon；配置 `GetMaterialApp`、命名路由、`InitialBinding`、页面 Binding 及应用级 `LocationSessionService`。创建自研 bridge 包与测试假实现，先跑通能力查询和命令事件，再把固定版本的 idevice 接入 Swift。验证 Android 模拟位置和 iPhone 27.0.1 单点设置、停止、恢复与断线状态。
2. **M1**：M0 验收通过后扩展 GetX 页面和命名路由，加入地图、非敏感设置和文件目录支持；确认瓦片供应商和坐标系，验证手输坐标与地图选点一致。
3. **M2**：路线引擎有明确合同后加入 GPX、文件选择与分享，核查原生工具链变化，完成坏文件与容量限制测试。

每个阶段的依赖接入至少完成：读取该版本 changelog 与发布包约束、执行 `flutter pub get`、检查实际 lockfile、静态分析与相关测试、Android 构建及 iOS 构建。涉及定位或原生生命周期的变化再完成相应真机验收。当前文档阶段未执行这些安装和构建，也尚未选定 idevice commit；具体门槛见 [开发规范](development-standards.md) 与 [开发路线](development-roadmap.md)。

以上候选版本是核实日快照，后续可能变化；是否可共同解析、是否满足所有传递插件要求及是否兼容目标真机，必须由实际接入结果确认。
