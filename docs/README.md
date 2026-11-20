# CLocation 开发文档

文档基线：2026-10-21。适用对象：项目开发者、代码评审者及参与开发的代理。

目标是开发 Android 与 iPhone 定位模拟 App。已确认的首批条件为 iPhone 16 Pro / iOS 27.0.1，个人使用或小范围测试，接受侧载。iOS 核心路线为本机配对、外部本地隧道和设备开发者服务；Android 核心路线为系统模拟位置。

## 阅读顺序

| 文档 | 内容 |
| --- | --- |
| [iOS 使用说明](ios-user-guide.md) | 安装准备、LocalDevVPN、本机配对、设置/恢复、错误排查与 Mac 辅助操作 |
| [Get CLI 工作流](get-cli-workflow.md) | CLI 版本、项目创建、页面生成与迁移记录 |
| [实现状态](implementation-status.md) | 当前功能、构建与测试证据、真机待验收项 |
| [iPhone 真机测试](validation/2026-10-21-ios-mac-location.md) | Mac 辅助模拟、微信 A/B 与恢复通过；首次 App 安装记录 |
| [iOS 手机端用户反馈](validation/2026-10-21-ios-user-feedback.md) | 安装 LocalDevVPN 后用户反馈测试成功；细分场景待补充 |
| [可行性研究](ios-location-feasibility.md) | 技术证据、平台差异、尚未验证的边界 |
| [三星免 Root 微信替代方案](wechat-no-root-feasibility.md) | 应用内加载、虚拟容器、限制与原型验收顺序；尚未实施 |
| [项目架构](architecture.md) | 分层、依赖、状态模型、原生桥接和数据流 |
| [目录结构与文件分类](directory-structure.md) | 目标目录树、文件归属、命名和提交规则 |
| [开发规范](development-standards.md) | 编码、异步、错误、存储、验证与交付约定 |
| [组件封装](component-guidelines.md) | 页面、业务组件、基础组件、地图与平台门面 |
| [三方依赖](dependencies.md) | 已有和候选依赖、版本、用途、约束与接入阶段 |
| [开发阶段与验收](development-roadmap.md) | 实现顺序、阶段出口和真机记录格式 |
| [项目流程图](project-flow.md) | 启动、平台前置条件、单点设置与恢复的分支流程 |
| [关键时序图](sequence-diagrams.md) | GetX 启动、iOS 配对、设置、停止和 Android 调用顺序 |
| [SVG 图示预览](diagrams/README.md) | 架构图、流程图和时序图的可缩放导出及源码入口 |
| [仓库约定](../AGENTS.md) | 后续开发须遵循的简明规则 |

## 当前工程与目标设计

当前工程由 `get_cli 1.9.1` 创建的 GetX Pattern 骨架迁入既有仓库，已实现启动、设备准备、定位工作台、GetxService、类型化桥接和双端原生代码。在线地图与路线暂未接入。已构建不等于已通过真机定位验收，详见 [实现状态](implementation-status.md)。

| 项目 | 当前核实值 | 开发约定 |
| --- | --- | --- |
| Flutter / Dart | 本机 SDK 3.44.2 stable / 3.12.2；项目 Dart 约束 `^3.12.2` | 先以此为开发基线，升级时单独核实插件及双端构建 |
| Xcode | 本机 27.0 | iOS 真机能力仍需验证，安装工具链不代表协议可用 |
| iOS deployment target | 已改为 26.0 | 仅代表最低安装目标；26.0 尚未真机验证，当前定位引擎仍要求 iOS 27+ |
| Android | 当前 Flutter 默认 minSdk 24、compileSdk 36、targetSdk 36 | 插件接入后重新核对，目标设备/API 版本进入真机记录 |
| iOS 首测设备 | iPhone 16 Pro / iOS 27.0.1 | Mac 辅助 A/B/恢复通过；手机端有用户成功反馈 |

SDK 值来自本机 Flutter 缓存元数据与 `FlutterExtension.kt`；项目配置来自 `pubspec.yaml` 和 `ios/Runner.xcodeproj/project.pbxproj`。这些值是本轮环境快照，不是所有候选包已能解析或构建的证明。

## 已确定的工程决策

1. Flutter 共用交互，iOS 与 Android 分别实现定位底层。
2. 状态管理、路由、依赖统一使用 `get: ^4.7.3`，模块目录采用 Get CLI 支持的 `getx_pattern` 形式。
3. 先验证能力探测、单点设置和清除，再接地图、收藏、路线等产品功能。
4. 单一原生会话负责串行执行，应用级 GetxService 提供只读快照，页面 Controller 负责交互；Flutter 通过类型化桥接获取状态。
5. 内部坐标统一 WGS84；不把地图坐标和平台坐标混用。
6. 首期无账号、云同步、后端数据库或内置 VPN 核心，外部隧道作为显式前置条件。

涉及插件、接口、目录或能力边界的实际变化，应在对应文档中同步更新。功能实施状态单独记录；架构、编译及测试均不能代替真机验证。
