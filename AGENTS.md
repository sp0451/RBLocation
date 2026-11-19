# CLocation 开发约定

适用于本仓库。文档入口为 `docs/README.md`，实现前阅读与改动有关的文档。

- 项目目标是 Android 与 iPhone 定位模拟。首批 iOS 验证设备为 iPhone 16 Pro / iOS 27.0.1，采用侧载、小范围测试路线。
- 当前已实现 M0 代码与原生桥接。构建和自动化测试不能代替真机验收；已验证状态见 docs/implementation-status.md。
- 状态管理、路由与依赖统一使用 `get: ^4.7.3`。必须使用 `get_cli 1.9.1` 创建工程和新增页面，选择 `getx_pattern`，保留其路由 part 和大写常量规范：`lib/app/modules/<module>/{bindings,controllers,views,widgets}`，共享数据和会话服务放 `app/data`、`app/services`。不要创建空分层或透传 UseCase。
- 用 GetMaterialApp、GetPage 和命名路由；InitialBinding 同步注册全局 Repository/LocationSessionService，Service 受管异步初始化并显示 loading/error。页面 Controller 由路由 Bindings 创建，Get.find 集中在装配点，数据模型与 Repository 不依赖 Get。
- LocationSessionService 为应用级 GetxService；页面 onClose 只清理本页订阅/Workers，不停止原生会话。显式 await shutdown 后再做测试 Get.reset，不能依赖 reset 清理异步资源。
- 原生层拥有设备会话和资源生命周期；Flutter 显示原生快照与事件。连接成功、命令成功、定位观测必须分别表达。
- 内部与平台接口统一使用经过校验的 WGS84 经纬度；地图坐标转换集中在地图适配器。
- 业务组件先放模块内部，满足实际跨模块复用再提升到 `app/widgets`。通用组件通过值和回调通信，不直接调用平台或 Get.find 全局查找业务对象。
- 配对密钥、原生句柄不进入 Dart、日志、版本库。公开诊断默认隐藏精确坐标和设备标识。
- 不手改生成代码；Pigeon 接口和各端生成产物一起更新。Rust 固定提交，header 与库由同一次构建产生。
- 停止操作必须使旧设置结果失效；断连不等于恢复定位；重连默认不重放旧设置命令。
- 新依赖按 `docs/dependencies.md` 的阶段引入，更新锁文件和选型记录，避免重叠职责。文档任务不顺带安装依赖。
- 验证随改动范围选择。定位状态机、异步竞态、坐标转换和资源清理需要有针对性的验证；纯文档改动检查内容和链接即可。
- 构建成功、协议返回成功、真机定位观测成功是不同证据，交付时分别说明。

详细规则见 `docs/development-standards.md`、`docs/architecture.md`、`docs/component-guidelines.md`。
