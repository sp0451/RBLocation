# location_bridge

CLocation 本地插件。公共门面为 `lib/location_bridge.dart`，Pigeon 类型留在内部；配对记录和 Rust 句柄不进入 Dart。

`pigeons/location_api.dart` 是通道定义源，固定 Pigeon 29.0.10。修改后从仓库根目录运行 `sh scripts/generate_bridge.sh`，三端生成文件同批更新，不手动修改。

Android 原生运行时管理模拟 provider、权限、前台通知、停止屏障与定位观测。iOS 原生运行时管理 Remote Pairing、Keychain、外部隧道、DVT 与 Core Location 观测。它们都将连接、命令和实际观测分开；`sent` 不能解释为目标 App 已改变定位。

iOS 底层来源与构建见 [PROVENANCE](../../native/idevice/PROVENANCE.md)，当前验收范围见 [实现状态](../../docs/implementation-status.md)。

