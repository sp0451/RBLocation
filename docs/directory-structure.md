# 目录结构与文件分类

工程和页面必须使用 `get_cli 1.9.1` 生成，选择 GetX Pattern。当前 M0 已按此生成并迁入现有原生实现；操作记录见 [Get CLI 工作流](get-cli-workflow.md)。以下包含 M0 目录和 M1/M2 规划，不代表所有目录均已创建。**按 [阶段计划](development-roadmap.md) 创建需要的目录，不预建空文件或空模块**。[Get CLI 官方说明](https://github.com/jonataslaw/get_cli)、[GetX Pattern](https://kauemurakami.github.io/getx_pattern/)

## 目标目录

```text
CLocation/
├── AGENTS.md                         # 仓库开发约定
├── README.md                         # 项目入口与当前状态
├── pubspec.yaml / pubspec.lock        # 应用依赖声明及解析结果
├── analysis_options.yaml             # 应用静态分析规则
├── lib/
│   ├── main.dart                     # Flutter 初始化与 GetMaterialApp，无业务逻辑
│   └── app/
│       ├── bindings/
│       │   └── initial_binding.dart # 同步注册应用级 Repository/Service
│       ├── routes/
│       │   ├── app_pages.dart       # GetPage 与 Binding 配置
│       │   └── app_routes.dart      # 路由名称常量
│       ├── services/
│       │   └── location_session_service.dart # 常驻 GetxService，只读 Rx 快照
│       ├── data/
│       │   ├── models/
│       │   │   ├── geo/wgs84_coordinate.dart
│       │   │   └── session/         # 快照、命令、观测、能力的纯 Dart 模型
│       │   ├── repositories/
│       │   │   ├── location_session_repository.dart # 纯 Dart 契约
│       │   │   └── native_location_session_repository.dart
│       │   ├── providers/
│       │   │   ├── native_location_provider.dart # 原生 bridge 数据源
│       │   │   ├── local_storage_provider.dart  # M1 本地文件与偏好
│       │   │   └── map/             # M1 地图源与坐标参考系适配
│       │   └── repositories/native_session_mapper.dart # 桥接类型映射
│       ├── core/
│       │   ├── error/app_failure.dart
│       │   ├── logging/redacting_logger.dart
│       │   └── time/clock.dart      # 有测试需要时抽取
│       ├── theme/                   # 颜色、间距、排版、ThemeExtension
│       ├── widgets/                 # 跨模块纯展示组件
│       └── modules/
│           ├── startup/             # 初始化状态、错误、导航选择
│           ├── device_setup/        # 配对、权限与隧道引导
│           ├── location_workspace/  # 主工作区，组合选点和会话面板
│           ├── coordinate_picker/   # 手动坐标，M1 增加地图
│           ├── location_session/
│           │   ├── bindings/location_session_binding.dart
│           │   ├── controllers/
│           │   │   ├── location_session_controller.dart
│           │   │   └── location_session_state.dart # 确有展示状态时创建
│           │   ├── views/location_session_view.dart # GetView<Controller>
│           │   └── widgets/         # 状态卡、操作栏、恢复提示
│           ├── favorites/           # M1，沿用 bindings/controllers/views
│           ├── settings/            # M1，简单模块不预建空目录
│           └── route_playback/      # M2；与 app/routes 路由配置区分
├── packages/
│   └── location_bridge/             # 自研本地 Flutter 插件
│       ├── pubspec.yaml
│       ├── pigeons/location_api.dart # 通道接口唯一源文件
│       ├── lib/location_bridge.dart # 插件公共门面
│       ├── lib/src/                 # 实现和类型映射
│       │   └── generated/location_api.g.dart
│       ├── ios/
│       │   ├── location_bridge/
│       │   │   ├── Package.swift    # SwiftPM 插件及本地二进制 target
│       │   │   ├── IdeviceRuntime.xcframework # 校验后的原生库
│       │   │   └── Sources/location_bridge/
│       │   │       ├── LocationBridgePlugin.swift
│       │   │       ├── Session/     # 串行会话、生命周期、命令队列
│       │   │       ├── Pairing/     # 本机配对及 Keychain
│       │   │       ├── Native/      # Rust C FFI 封装
│       │   │       └── Generated/LocationApi.g.swift
│       │   └── location_bridge.podspec # 若保留 CocoaPods 回退，引用同一份源
│       ├── android/src/main/
│       │   ├── AndroidManifest.xml
│       │   ├── kotlin/com/clocation/location_bridge/
│       │   │   ├── LocationBridgePlugin.kt
│       │   │   ├── MockLocationService.kt
│       │   │   └── generated/LocationApi.g.kt
│       │   └── res/                 # 通知图标等原生资源
│       └── test/                    # 门面、类型映射与桥接测试
├── native/
│   └── idevice/
│       ├── Cargo.lock              # 固定 Rust 传递依赖
│       ├── source/                 # 固定提交源码归档
│       ├── patches/aurora-ios.patch # 固定 MIT 配对和 DVT 补丁
│       ├── scripts/build-ios.sh    # 校验输入并生成库与头文件
│       ├── licenses/
│       └── PROVENANCE.md           # 来源、工具链、ABI 与重建说明
├── artifacts/ios/                   # 原生产物 manifest、来源及获取记录
├── android/                         # Android 应用宿主，保留薄 MainActivity
├── ios/                             # iOS 应用宿主、签名与生命周期接入
├── assets/                          # M1 实际引用的图片、图标、资源许可
├── test/                            # 与 lib 功能对应的 Dart/Widget 测试
├── integration_test/                # 实现后按需创建
├── scripts/                         # 实际使用的生成/构建/校验脚本
└── docs/                            # 设计、阶段计划、来源与脱敏验收记录
    └── diagrams/                    # Mermaid 的 SVG 导出及预览索引
```

`app/bindings/initial_binding.dart` 注册全局 Repository 与常驻会话 Service；模块 Binding 用 `Get.lazyPut` 注册页面 Controller，View 通过 `GetView<T>` 获取。Controller 构造注入应用服务或 Repository，不在方法中查找全局对象。Provider 表示数据源，不是额外状态管理框架。小规模 UI State 可与 Controller 同目录。自研桥接插件有独立 `pubspec.yaml`，首期通过 path dependency 接入，不要求发布 pub.dev。

本机 Flutter 3.44.2 对应的首选接入方式为 Swift Package Manager。Swift 源码和 Pigeon 输出放在 `ios/location_bridge/Sources/location_bridge/`，XCFramework 放包内 `IdeviceRuntime.xcframework` 以供 `Package.swift` 的本地 binary target 引用；如果保留 CocoaPods 回退，podspec 引用同一份源码，不维护两套 Swift 文件。[Flutter 插件 SwiftPM 指南](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors)

`artifacts/ios` 存放产物来源与校验 manifest，记录插件包内的实际库路径。库可随代码受控提交，或由已固定来源的脚本获取到相同路径；构建前校验，不能依赖开发者个人目录。临时库、DerivedData 和原生编译中间文件不放入该交付目录。

## 文件分类和归属

| 类别 | 命名/位置 | 维护规则 |
| --- | --- | --- |
| 领域值对象 | `app/data/models/`，坐标在 `models/geo/` | 不含 GetX、UI、插件类型或持久化路径 |
| UI State | `app/modules/<module>/controllers/*_state.dart` | 展示所需的不可变状态；不复制原生会话权威状态机 |
| Controller | `*_controller.dart` | 编排用户意图，调用 Repository 接口 |
| Binding | `app/bindings/`、模块 `bindings/*_binding.dart` | 同步装配依赖；不等待配对、连接等异步任务 |
| Repository 接口 | `app/data/repositories/*_repository.dart` | 表达稳定业务契约，不导入 GetX |
| Repository 实现 | `app/data/repositories/native_*_repository.dart` | 聚合、映射与存储协调 |
| Provider / Adapter | `app/data/providers/`、其 `map/` 子目录 | 对接一种外部来源，不含 Get.find 或 Widget |
| 应用级 Service | `app/services/*_service.dart` | 常驻 GetxService，显式 shutdown，不随页面销毁 |
| DTO / Mapper | Data 层，`*_dto.dart`、`*_mapper.dart` | 边界复杂才创建，简单模型不重复拷贝一套 |
| View 与组件 | 模块 `views/*_view.dart`、`widgets/` | View 用 GetView；纯组件按 [组件规范](component-guidelines.md) 提升到 app/widgets |
| Pigeon schema | `pigeons/location_api.dart` | 接口唯一手工维护源 |
| 生成代码 | 明确的 `generated/` 与 `.g.*` | 带生成头，不手改，与 schema 同批提交 |
| 配置 | `pubspec.yaml`、plist、Manifest、Gradle、Cargo | 能说明用途，不含个人签名或私钥 |
| 测试 | `test/`、平台测试目录，镜像对应模块 | 输入、可观测结果、异常边界清晰 |
| 原生交付产物 | 插件包内 `IdeviceRuntime.xcframework` 与 `artifacts/ios` 的 manifest | 记录来源提交、工具链、目标架构、实际路径和 SHA-256 |
| 文档与验收 | `docs/`；真机记录建议 `docs/validation/` | 来源可追踪、标明已测/未测，坐标和设备信息脱敏 |
| 流程与时序图 | `docs/project-flow.md`、`docs/sequence-diagrams.md` | Mermaid 为可编辑源；`docs/diagrams/*.svg` 为生成预览，更新源码后同步导出 |

不要新增无边界的 `utils.dart`、`common.dart`、`manager.dart` 或把所有模型放根目录 `models/`。能用具体责任命名时，用 `CoordinateFormatter`、`SessionEventReducer` 等名称。

## Get CLI 的使用范围

项目创建和新增页面必须使用 Get CLI，不手工搭建一套近似目录。`get create page:device_setup` 会生成 Controller、View、Binding 并登记路由。路由遵循 CLI 输出：`app_routes.dart` 是 `app_pages.dart` 的 part，页面导航导入 `app_pages.dart` 并使用 `Routes.DEVICE_SETUP` 等大写常量。生成后补充构造注入与业务实现，应用服务和原生会话不放入页面生命周期。

`get init` 会覆盖 `lib`，已有工程不能直接运行。完整命令、实际迁移记录及 CLI 版本见 [Get CLI 工作流](get-cli-workflow.md)。[官方 Init 与页面生成说明](https://github.com/jonataslaw/get_cli#init)

## 生成代码和产物提交

桥接包接入 Pigeon 后，在 schema 中配置输出路径，从插件目录运行：

```sh
dart run pigeon --input pigeons/location_api.dart
```

当前插件已创建，使用根目录 `sh scripts/generate_bridge.sh` 同步生成三端；不要单独修改或格式化生成文件。Pigeon 固定为 29.0.10。

应用 `pubspec.lock` 必须提交；桥接插件如保留独立 lock 文件，应明确其独立测试用途，根应用最终解析仍以根锁文件为准。Rust 提交 `Cargo.lock`；原生 `.a` 与 header 必须来自同一次构建。二进制较大时采用受控产物存储并提交 manifest 与获取脚本，不能只留下不可访问的个人路径。

## 不进入版本库的文件

构建缓存、`.dart_tool`、DerivedData、临时下载和本地 SDK 路径不提交。配对记录、PIN、私钥、证书、个人 provisioning profile、`.env` 中的凭据及未脱敏设备日志不提交。当前 `.gitignore` 是 Flutter 基础模板，接入各模块时补充相应规则；不要把本节当作忽略规则已经配置完成。
