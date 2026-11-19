# iPhone 定位模拟可行性研究

研究日期：2026-10-19。目标设备：iPhone 16 Pro / iOS 27.0.1。用途：个人或小范围测试，可接受侧载。用户当前要求先研究可行方案。

后续进展（2026-10-21）：本页保留初期研究快照。当前已实现原生桥接并签名安装启动；Mac 辅助路线已在该 iPhone 的微信 8.0.79 位置选择页通过上海、北京与清除恢复测试。App 内独立配对及隧道尚待验收。现状以 [实现状态](implementation-status.md) 与 [真机记录](validation/2026-10-21-ios-mac-location.md) 为准，下文“未接入”等措辞仅指研究当时。

## 结论

存在让其他 App 读到模拟位置的实现路线，值得进入真机验证。推荐方向是：侧载 iPhone App，通过本机配对和本地隧道访问设备的开发者定位模拟服务。现阶段只能确认技术路线存在，不能确认已经兼容这台设备或用户的目标 App。

一手实现依据：[Locus](https://github.com/ChrisMack32/Locus) 使用 idevice FFI 接入 DVT 定位模拟，说明 iOS 27 可通过系统六位码完成本机配对，并报告 Maps 等 App 能读到模拟位置。这是项目作者的实现说明，本次未复现。

## 路线比较

| 路线 | 使用方式 | 对当前目标的判断 |
| --- | --- | --- |
| 手机端开发者服务 | 侧载 App、开发者模式、配对记录、本地隧道；准备完成后在手机上操作 | 首选验证方向；后台、蜂窝和恢复行为需实测 |
| 电脑端开发者服务 | Mac/Windows 辅助程序连接已配对 iPhone 并设置位置 | 可作为验证基线或手机端失败时的备选 |
| 普通 iOS App 的公开定位 API | 获取设备位置、管理本 App 的定位使用 | 没有发现支持改写其他 App 所读设备位置的公开接口 |
| Xcode 测试计划 / GPX | 调试或测试指定代码 | Apple 的 test plan 模拟明确限定 test bundle，不能据此保证影响任意第三方 App |

公开接口范围依据：[Core Location](https://developer.apple.com/documentation/corelocation)。测试范围依据：[Apple 的位置测试说明](https://developer.apple.com/documentation/xcode/simulating-location-in-tests)。手机方案依据：[Locus](https://github.com/ChrisMack32/Locus)、[StikDebug](https://github.com/StikDebug/StikDebug)。电脑方案依据：[pymobiledevice3 DVT 命令源码](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/cli/developer/dvt/simulate_location.py)。

## iOS 27.0.1 需要特别核实的部分

- 本机配对：Locus 说明 iOS 27 支持通过 Developer Mode 内的 Pair with Host 和六位码完成 Remote Pairing。因此不应沿用“所有版本都必须先在电脑生成配对文件”的判断。App 安装、设备准备和配对是三个独立环节。
- 设备准备：部分实现仍要求 Xcode 先准备设备并使 Developer Disk Image 服务可用。本机配对不等于完整安装和启动流程已经完全摆脱电脑。
- 网络：先以 Wi-Fi + LocalDevVPN 验证。Wi-Fi 转蜂窝、纯蜂窝首次建连、其他 VPN 共存应分别测试。
- 后台与恢复：不能承诺无限后台、锁屏长期保持或重启后保持；停止命令发送成功也不等于已经重新取得真实定位。

上述边界可交叉参考 [Locus 的连接说明](https://github.com/ChrisMack32/Locus) 和 [Aurora Location 的要求与验收限制](https://github.com/AuroraNest/Aurora-Location)。Aurora 文档包含阶段性成功反馈，同时保留长期锁屏、故障恢复等未完成验收项；这些反馈不能替代本项目实测。

## 推荐的实现结构

以下为本项目的工程建议，尚未实现：

- Flutter：共用地图选点、手动坐标、收藏和会话界面。
- iOS：Swift 管理系统权限、配对交互和生命周期，封装 Rust idevice 的开发者服务能力，向 Flutter 提供能力查询、连接、设置位置、清除位置和错误事件。
- Android：Kotlin 接入系统模拟位置 API，由用户在开发者选项选择本 App。界面共用，底层分别实现。
- 配对记录：保存在本机受保护存储中，诊断信息不包含配对密钥。

底层应固定经过验证的源码版本，并从同一版本构建 C header 和静态库。idevice 提供 Rust 库及 FFI，但项目明确仍处于开发研究阶段，接口可能变化。[idevice 项目说明](https://github.com/jkcoxson/idevice)

协议层已有直接证据：pymobiledevice3 的 [LocationSimulation 实现](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/dvt/instruments/location_simulation.py) 通过 `com.apple.instruments.server.services.LocationSimulation` 通道发送设置与清除请求。这属于设备开发者服务协议，不能等同于面向普通 iOS App 的公开“设置系统 GPS”接口。

参考项目选择：idevice 与 Locus 标注 MIT，可作为后续实现研究入口；StikDebug 标注 AGPL-3.0，复用其代码时需按对应许可处理。Roam Control 当前为专有软件且不公开应用源码，仅用作产品能力存在的参考。[idevice](https://github.com/jkcoxson/idevice)、[Locus](https://github.com/ChrisMack32/Locus)、[StikDebug](https://github.com/StikDebug/StikDebug)、[Roam Control](https://github.com/seanhowarthdev/Roam-Control)

## 第一次真机验证

建议先验证单点设置和恢复，通过后再开发地图、路线和摇杆。以下均未执行：

| 验证项 | 通过依据 |
| --- | --- |
| 配对及开发者服务连接 | 目标设备身份匹配，实际握手成功；不能仅看 VPN 已连接 |
| 设置坐标 A、再设置 B | Apple Maps 与独立 Core Location 测试 App 都观察到变化 |
| 用户指定的目标 App | 单独记录每个 App 是否接收、缓存或拒绝位置 |
| 切后台、锁屏 | 在 1、5、15 分钟观察并记录保持时间 |
| 网络变化 | 分别验证 Wi-Fi、切换蜂窝、纯蜂窝新建连接 |
| 停止与恢复 | 观察系统重新取得真实位置；记录恢复耗时与失败情况 |
| 隧道断开、强制退出、重启 | 明确实际位置与会话状态，避免界面误报仍在模拟 |

不能保证所有 App 都接受模拟结果。Apple 提供 `isSimulatedBySoftware` 来源标记，接收位置的 App 可据此处理模拟位置。[Apple 来源标记说明](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware)

## 分发与当前范围

按用户接受的侧载、小范围测试目标评估。不能据此承诺普通 App Store 分发可行；Apple 审核规则要求公开 API，StikDebug 当前也明确已不在 App Store。[审核规则 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)、[StikDebug 分发说明](https://github.com/StikDebug/StikDebug)

本次只做文档和源码调研，没有安装第三方 IPA、导入配对记录或修改任何手机定位。工作区保留 Flutter 初始工程，未接入上述服务。

本机另外验证了 Xcode 27.0 的命令帮助：`xcrun devicectl device simulate location --help` 列出 coordinate、route、clear 等子命令。这证明本机工具链具有相应命令入口，尚未验证其对目标真机的实际效果。
