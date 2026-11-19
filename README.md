# CLocation

Android / iPhone 定位模拟 M0 原型。工程由 **get_cli 1.9.1** 创建，采用 GetX Pattern；状态管理、依赖注入和路由使用 **get: ^4.7.3**。

iPhone 用户入口：[iOS 使用说明](docs/ios-user-guide.md)，包含首次准备、手机端操作、错误排查和已实测的 Mac 辅助方式。

已实现手动 WGS84 输入、设备准备、配对交互、连接、设置、停止，以及独立的命令与定位观测面板。Android 使用系统模拟位置和前台服务；iOS 使用本机 Remote Pairing、外部 LocalDevVPN 与固定版本 idevice Rust 库。

工具链基线：Flutter 3.44.2 / Dart 3.12.2、Android API 24+、Xcode 27 / iOS 27.0+。Android 已在 Samsung SM-G990U2 / Android 12 通过单点设置、Google Maps 观测和停止恢复的[真机测试](docs/validation/2026-10-20-android-mock-location.md)。iPhone 16 Pro / iOS 27.0.1 已通过 Mac 辅助设置上海、北京及清除恢复，微信 8.0.79 位置选择页生效；用户随后反馈安装 LocalDevVPN 后手机端测试成功。[Mac 真机记录](docs/validation/2026-10-21-ios-mac-location.md)、[手机端用户反馈](docs/validation/2026-10-21-ios-user-feedback.md)。完整状态见 [实现状态](docs/implementation-status.md)。

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Android 默认启用国内 Maven / Flutter 引擎镜像，普通 `flutter run` 无需临时 Gradle 脚本。使用标准仓库时将 `android/gradle.properties` 的 `clocation.useChinaMirrors` 改为 `false`；排障记录见 [Android 构建验证](docs/validation/android-build.md)。

项目和新增页面使用 CLI 生成，实际创建记录及命令见 [Get CLI 工作流](docs/get-cli-workflow.md)。其他入口：[开发文档](docs/README.md)、[架构](docs/architecture.md)、[流程图](docs/project-flow.md)、[时序图](docs/sequence-diagrams.md)、[iOS 底层来源与重建](native/idevice/PROVENANCE.md)。

已知 Android 兼容性限制：三星上微信 8.0.79 的位置选择页未采用模拟结果，Google Maps 的通过不代表微信通过。详见 [微信兼容性复核](docs/validation/2026-10-21-android-wechat-compatibility.md)。此结果与 iPhone 的 Mac 辅助测试分别记录。

三星替代方案研究按“当前三星、免 Root”限定，应用内加载与虚拟容器尚为未实施候选，见 [替代方案与验证顺序](docs/wechat-no-root-feasibility.md)。
