# 开发规范

本项目采用 GetX 模块结构，状态管理、依赖注入和路由统一使用 `get: ^4.7.3`。工程与页面通过 `get_cli 1.9.1` 生成，选择 GetX Pattern；现有 M0 已接入 GetX。具体边界见 [项目架构](architecture.md)，文件归属见 [目录规范](directory-structure.md)。Dart 风格参照 [Effective Dart](https://dart.dev/effective-dart/style)，GetX API 参照 [4.7.3 发布版本](https://pub.dev/packages/get/versions/4.7.3)。

## 编码与命名

| 对象 | 规则 | 示例 |
| --- | --- | --- |
| Dart 文件和目录 | `snake_case` | `location_session_controller.dart` |
| 类型、枚举、扩展 | `UpperCamelCase` | `SessionSnapshot`、`Wgs84Coordinate` |
| 变量、方法、常量 | `lowerCamelCase` | `lastAcknowledgedCoordinate`、`connectTimeout` |
| Flutter 页面 | `XxxView`，文件 `xxx_view.dart` | `DeviceSetupView`；与 Get CLI 生成习惯一致 |
| 功能状态与控制器 | `XxxState`、`XxxController` | `CoordinatePickerState` |
| 页面依赖装配 | `XxxBinding extends Bindings` | `DeviceSetupBinding`、`InitialBinding` |
| 仓储接口与实现 | `XxxRepository`、`XxxRepositoryImpl` | `LocationSessionRepositoryImpl` |
| 数据来源与外部适配器 | `XxxProvider` / `XxxAdapter`；不是状态管理 Provider | `NativeLocationProvider`、`FlutterMapAdapter` |
| 应用级服务 | `XxxService extends GetxService`，只用于需要应用生命周期的服务 | `LocationSessionService` |
| Swift / Kotlin 源文件 | 随平台习惯用类型名 | `LocationSessionRuntime.swift`、`MockLocationService.kt` |

- Dart 使用 formatter 的结果；优先 `final`、不可变模型、具名参数及可表达缺省的 nullable 类型。
- 不用 `dynamic` 或未约束的 `Map<String, dynamic>` 跨越业务和平台边界。仅在 JSON/协议适配处解析并立即转换成类型化对象。
- `build()` 只做展示、布局和事件绑定；不在其中写文件、连接设备、发定位命令或触发权限弹窗。
- 一份文件围绕一个主要职责；紧密相关的私有小类型可放一起。不按任意行数拆出无意义文件。
- 注释说明约束和选择原因。TODO 附上待满足条件或具体后续事项，不留下无解释的“以后优化”。
- 用户文案集中管理，预留 Flutter 本地化接入；首期中文。类型、方法和协议字段使用英文，诊断错误码稳定。
- 业务状态统一用 GetX 的 Rx / `Obx`，页面展示控制器继承 `GetxController`；焦点、动画、展开状态等局部交互可用 Widget 自有状态。
- Rx 字段保持私有，通过只读值 getter 或只读 Stream 暴露；外部通过语义化方法修改，不直接写 `controller.xxx.value`。一个原生会话只保留一份应用级快照来源，页面可派生展示数据，不能各自维护独立原生状态机。
- `Obx` 只包实际读取响应值的必要 UI，避免心跳触发整页或整张地图重建。不要用 `Obx` 与 `GetBuilder` 同时管理同一份状态。
- `build()`、`Obx` 回调和 Controller 初始化不重复发送定位命令；重建页面只恢复订阅和读取快照，设置/停止均由明确用户操作触发。

## 分层和依赖注入

- 目录采用 `lib/app/{bindings,modules,routes,data,services,core,widgets,theme}`。模块放 `modules/<module>/{bindings,controllers,views,widgets}`；公共数据放 `data/{models,repositories,providers,mappers}`。按需创建，不能先创建空模块或空分层。
- Repository 接口表达业务需要，位于 `app/data/repositories`；其实现协调 Provider 与 mapper。`Provider` 在本项目仅表示数据来源适配器，例如 `NativeLocationProvider` 调用自研 bridge，不代表另一套状态管理。
- 纯业务模型、坐标校验、Repository 接口不导入 Flutter、GetX、Pigeon 生成代码、地图插件或 Swift/Kotlin 协议细节。通用错误位于 `app/core/error`，WGS84 坐标模型位于 `app/data/models/geo`。
- `InitialBinding` 负责应用级依赖装配；各路由 `Binding` 用 `Get.lazyPut` 装配页面 Controller。`Get.find` 仅出现在 Binding 或 View 装配点；Controller 使用构造注入，不在方法中隐式查找全局依赖。
- `LocationSessionService` 构造注入 `LocationSessionRepository` 接口，集中订阅快照和协调会话操作；`LocationSessionController` 构造注入该应用级服务。其他不涉及会话协调的 Controller 依需要注入 Repository 接口。UI 不绕过服务重复调用同一原生会话。
- 功能间只访问公开契约或稳定组合组件，不直接访问其他模块内部 Controller、Binding 或 View。跨模块复用的数据与服务放入 `app/data` 或 `app/services`，不互相注册对方页面控制器。
- 不再并行引入其他状态管理、独立路由框架或全局 Service Locator。GetX 自带的 `GetConnect` 等能力不因安装 GetX 自动纳入架构，有明确网络需求时再单独选型。
- 简单功能不强制额外 UseCase；出现跨来源聚合或重复业务算法时再新增纯 Dart 协作对象，不创建透传 UseCase 或通用 Repository 基类。

## GetX 路由与生命周期

1. 根组件使用 `GetMaterialApp(initialBinding: InitialBinding(), getPages: AppPages.routes, ...)`。命名路由集中在 `app/routes/app_routes.dart`，`GetPage` 列表位于 `app/routes/app_pages.dart`，页面与其 `Binding` 一起登记。M0 即使用相同路由方案，后续逐步加入设置、诊断和地图页面。
2. 导航使用路由常量与 `Get.toNamed` 等命名 API，返回用 `Get.back`。跳转由 View/页面层处理，叶子组件只回调意图；参数在入口做类型和取值校验，不通过 `Get.arguments` 传配对凭据、原生句柄或完整精确位置历史。
3. `InitialBinding.dependencies()` 同步注册 Repository 与 `LocationSessionService`，使用 `Get.put(..., permanent: true)` 保持应用生命周期，整个 bootstrap 只装配一次。`Bindings.dependencies()` 不能等待异步设备连接；服务在 `onInit` 启动受管理的异步 attach 流程，公开初始化 loading/error，进入 ready 前禁用会话命令。异步任务明确处理异常，不能使用未受管的 `async void`。
4. `LocationSessionService extends GetxService` 不绑定任一路由，不用 `fenix` 自动重建。服务持有原生快照订阅和私有 Rx，原生层仍拥有真实会话、句柄与命令队列。页面 Controller 从服务派生展示状态，不复制会话权威状态。
5. 页面 Controller 的 `onInit` 只建立所需 UI 订阅或 workers、读取已有快照；`onClose` 释放自身创建的 workers、Stream 订阅、文本和滚动控制器。离开页面不关闭应用级服务，不停止模拟、不清除原生会话。
6. 常驻服务必须提供可等待、可重复调用的显式 `shutdown()`，按 [架构](architecture.md) 的停止与资源释放合同处理，并报告清除结果。正常停止按钮执行清除操作；不以删除 Get 注册或销毁页面代替停止。系统直接结束进程时不能承诺 `shutdown()` 一定执行。
7. `Get.reset()` 仅用于测试 teardown，先等待服务 `shutdown()` 和订阅释放再清理注册表。生产中不得用它切换设备、停止定位或重启服务。默认的页面自动清理不能扩展到原生会话资源。

GetX 生命周期 API 与依赖注入语义参考 [4.7.3 包说明](https://pub.dev/packages/get/versions/4.7.3)；本项目对全局查找、显式停止和重建的限制属于工程约定。工程和新增页面必须使用 `get_cli 1.9.1` 生成，保留 Controller/View/Binding 和路由 part 结构。迁移已有代码前备份，不能直接执行会替换 `lib` 的 `get init`。实操见 [Get CLI 工作流](get-cli-workflow.md)。

## 异步、取消与生命周期

1. 对连接、配对、设置、清除和文件写入分别定义超时、错误和清理行为；超时必须在原生/服务层处理，不能只让 Dart Future 超时。
2. 原生层拥有会话、心跳、FFI 句柄和任务。离开页面只取消 UI 订阅，不隐式销毁应用级会话。
3. 重复点击由 Controller 防重复触发，原生层仍须通过命令队列和命令标识保证执行一致性。
4. Swift actor 在 `await` 时可能重入，必须另有显式队列或互斥以及会话代次检查。
5. “取消请求”与“命令未执行”分别表达。已经发送的设置请求无法确认撤销时，进入结果未知状态，保留清除入口。
6. 停止请求丢弃尚未发送的设置，失效旧完成回调；正在执行的协议请求按可取消能力终止或等其结束后清除。清除期间拒绝新设置，终结后由用户重新提交，旧任务不能重新排队。
7. 网络断开、App 挂起或进程消失不能作为真实定位已恢复的依据。重新打开时先读取原生快照，不恢复旧的“运行中”界面。
8. 重连仅恢复连接，默认不重放改变位置的旧命令。时间戳用于展示和证据，事件排序使用序号，不依赖设备墙上时钟。

## 坐标与单位

- 业务坐标类型 `Wgs84Coordinate` 仅接受有限数值；纬度 `[-90, 90]`、经度 `[-180, 180]`，拒绝 NaN、Infinity、空输入与含糊格式。
- 显示精度和存储精度分离，避免格式化后再解析造成不必要截断。
- 从地图供应商进入的数据标记坐标系；GCJ-02、BD-09 等转换在适配边界完成并测试。平台接口只接收 WGS84。
- 纬度在前、经度在后；桥接使用具名字段，禁止传无说明的两元素数组。
- 距离、精度用米，速度用米/秒，持续时间用有单位的类型或字段名。UTC 时间用于持久化，界面转换本地时间。

## 错误和诊断

统一使用结构化失败信息：`code`、`stage`、`retryable`、`recoveryAction`、`operationId`，界面根据错误码生成中文说明。原生异常须映射，未知异常保留脱敏的技术摘要，禁止空 catch 或把失败返回成成功默认值。

首期错误至少区分：`unsupportedPlatform`、`unsupportedOsVersion`、`permissionDenied`、`developerModeRequired`、`pairingRequired`、`tunnelUnavailable`、`developerServiceUnavailable`、`mockAppNotSelected`、`invalidCoordinate`、`operationInProgress`、`operationTimedOut`、`connectionLost`、`operationCancelled`、`resultUnknown`、`clearFailed`。能力探测无法明确判断的前置条件返回 unknown，不能伪造 ready。命令仅写出与服务回执采用不同证据等级，FFI 无错误不自动等于服务确认；位置观测另外表达。

日志记录阶段、命令标识、耗时和脱敏状态。配对凭据、PIN、私钥、完整配对记录不写入日志；设备标识和精确坐标默认隐藏。敏感字段不进入路由参数、剪贴板自动复制或崩溃上报。

## 本地数据与配置

- 非敏感开关使用 Preferences，收藏及以后路线用有版本的本地文件，由 Repository 统一访问。
- JSON 文件包含 `schemaVersion`，写入采用同目录临时文件加替换及串行写入；读取损坏要保留可恢复副本并返回可解释的错误，不直接覆盖用户数据。
- iOS 配对信息由原生 Keychain 管理，Dart 只接收“是否已配对”等脱敏结果。
- 不持久化 `connected=true`、`simulationActive=true` 作为下次启动的事实。原生可保存带时间的未完成操作记录作恢复提示，但不能自动重放；新进程的 disconnected 默认值不能清除旧的恢复要求，定位效果先视为 unknown。
- 环境配置按类型注入：瓦片源、超时和日志级别等。`--dart-define` 不是密钥保险箱，嵌入 App 的普通 API key 应按供应商要求限制权限和应用来源。
- 地图瓦片访问会向供应商发送请求；诊断导出和历史保存分别提供明确操作，测试配对文件不得随报告提交。

## 验证和交付

对新增业务优先测试可出错的行为：坐标校验、状态转换、事件顺序、停止优先级、超时、失败清理和文件损坏恢复。使用 fake Repository/原生传输，不做仅复述实现的测试。Controller 单测可手工创建服务与 fake Repository 后构造注入，不必依赖全局 Get 注册；路由与 Binding 的集成测试再验证注册和生命周期。验证离开页面不停止会话、重复进入不重复订阅或重发命令、服务关闭后不接收旧事件。纯文案、格式或文档改动无需添加实现镜像测试。

当前 M0 已包含应用、桥接包、测试和固定 Rust 原生产物。常用检查命令：

```sh
# 应用目录；不单独格式化 Pigeon 生成文件
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

# 原生功能接入后的构建验证
flutter build apk --debug
flutter build ios --debug --no-codesign
```

桥接包另行执行其分析和测试；Rust crate 执行 `cargo fmt --check`、`cargo clippy`、`cargo test --locked`。无签名 iOS 构建只验证编译，Simulator 不能证明真机配对或定位模拟成功。

每次交付说明改动行为、验证范围与剩余限制。提交建议使用 `feat:`、`fix:`、`refactor:`、`docs:`、`test:`、`chore:` 前缀；一次提交集中解决一个问题，不混入签名配置、密钥或无关依赖升级。涉及能力宣称的变化必须有对应的真机证据，记录格式见 [开发阶段与验收](development-roadmap.md)。
