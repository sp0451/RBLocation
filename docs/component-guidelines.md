# 组件封装规范

封装目标是稳定输入输出和隔离变化。业务组件从 `app/modules/<module>/widgets` 开始，存在两个独立模块的实际复用、参数语义稳定且不依赖原模块时，再提升到 `app/widgets`。不要仅因外观相似创建拥有大量模式开关的通用组件。目录遵循 Get CLI 的模块思路，页面使用 `XxxView`，具体路径见 [目录结构](directory-structure.md)。M0 已实现坐标输入、会话状态卡、操作栏、前置条件列表与临时配对面板；地图等组件仍按后续阶段创建。

## 四种封装层次

| 层次 | 放置位置 | 约束 |
| --- | --- | --- |
| 设计基础 | `app/theme` | 颜色、文字、间距、圆角、ThemeExtension；无业务状态 |
| 跨功能基础组件 | `app/widgets` | 只接值与回调，不访问 Get 全局依赖、设备服务或页面路由 |
| 业务组件 | `app/modules/<module>/widgets` | 表达功能语义，复杂行为交给 Controller，通过参数和回调通信 |
| 页面/工作区 | `app/modules/<module>/views/*_view.dart` | `XxxView extends GetView<XxxController>`，组装组件、用 `Obx` 订阅必要状态、处理路由和用户事件 |

优先使用 Material 现成控件。只有需要统一行为、可访问性或多个页面的视觉规则时才封装 `AppButton` 等基础组件；不为了改名给每个 Flutter 控件包一层。

## 计划组件及边界

以下是候选组件，按阶段创建，不表示当前已存在。

| 组件 | 主要输入 | 输出 | 边界 |
| --- | --- | --- | --- |
| `CoordinateInput` | 初值、enabled、校验结果 | 校验后的 `Wgs84Coordinate` 或提交事件 | 输入组件不发送定位命令，保留用户尚未完成的文本 |
| `CoordinatePickerPane` | 选中坐标、地图配置 | 选点、提交坐标回调 | 手输与地图选择统一；不读取会话连接状态 |
| `MapCanvas`（M1） | WGS84 目标点、可选观测点、交互开关 | 显式选点回调 | 第三方地图类型封装在内部，不暴露 `MapController` / `LatLng` 给业务 |
| `SessionStatusCard` | 连接、命令和观测的展示模型 | 展开诊断回调 | 放 `location_session`，不用一个绿灯代表全部成功 |
| `LocationActionBar` | 是否可设置/清除、等待状态、恢复要求 | 设置、清除回调 | UI 禁用用于交互，原生仍需并发保护 |
| `RecoveryNotice` | 恢复原因、可用恢复操作 | 重试清除、前往设置 | 位于会话功能内，清除失败时不能简单隐藏 |
| `PrerequisiteChecklist` | satisfied/missing/unknown 条目 | 操作条目的回调 | 位于 `device_setup`，只能跳转实际支持的系统设置入口 |
| `PairingInteractionPane` | 配对交互类型、提交状态、错误提示 | 临时验证码响应、确认、取消 | 按实际协议角色显示/输入验证码；不写会话快照、日志或持久化，退出清空 |
| `FavoritePlaceTile`（M1） | 名称、坐标摘要、选中态 | 选择、重命名、删除 | 位于 `favorites`，选择收藏不自动改变手机位置 |
| `EmptyState` / `InlineError` | 文案、图标、可选操作 | 操作回调 | 确有复用后进入 `app/widgets`，不绑定特定错误码 |

业务模型经 Controller 转为展示数据，基础组件不自行解释平台错误。View 通过 `GetView` 获取当前路由 Binding 注入的 Controller，`Obx` 在 View 或必要的组合节点读取只读 getter；叶子展示组件优先使用纯参数。View 不注册依赖，`Get.put`、`Get.lazyPut` 和 Repository 装配留在 Binding；不在组件中任意 `Get.find` 查找服务。局部表单焦点与输入文本可留在 StatefulWidget，不能因此维护第二份原生运行状态。

会话 View 使用的 `LocationSessionController` 构造注入应用级 `LocationSessionService`；服务持有原生快照，页面仅派生展示。其他页面 Controller 按需要构造注入 Repository 接口。页面 `onClose` 释放 UI 订阅和 workers，离开页面不会停止原生会话。服务初始化期间应明确显示 loading/error，在 ready 前禁用定位命令。

## GetX 组件组合

以下为实现形态示意，具体类型与字段以落地接口为准；不表示代码已存在。

```dart
class LocationSessionView extends GetView<LocationSessionController> {
  const LocationSessionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 状态 getter 在 Obx 中读取，值对象交给纯展示组件。
          Obx(() => SessionStatusCard(status: controller.status)),
          Obx(() => LocationActionBar(
                canSet: controller.canSet,
                canClear: controller.canClear,
                isPending: controller.isPending,
                onSetRequested: controller.submitSelectedCoordinate,
                onClearRequested: controller.clearSimulation,
              )),
        ],
      ),
    );
  }
}
```

Controller 的 Rx 是私有实现细节，对外提供 `status`、`canSet` 等只读 getter 和语义化方法。Leaf Widget 不接收 `Rx<T>`，也不修改响应容器；同一状态不用 `GetBuilder` 再维护一套更新入口。命名路由由 View 处理，例如 `Get.toNamed(Routes.deviceSetup)`，按钮组件只暴露 `onSetupRequested` 回调。GetX 的可用 API 以 [4.7.3 发布版本](https://pub.dev/packages/get/versions/4.7.3) 为准。

## 参数、回调与副作用

- 必需参数显式 `required`，可空参数有业务含义。互斥模式使用枚举或不同组件，避免多个 bool 形成非法组合。
- 组件接收“选中点”“历史发送/确认设置点”“最近观测点”时用不同参数，不能用一个 `currentLocation` 混淆三者；历史请求坐标不能伪装成当前实际位置。
- 回调名表达意图：`onCoordinateSubmitted`、`onClearRequested`，不使用含糊 `onChange` 承担多种操作。
- 组件不偷偷导航、弹权限或连接平台。配对等需要系统交互时，由 Controller 调用 Repository，并在界面展示其阶段。
- `build`、`Obx` 重建和 Controller 初始化不得重发定位命令。交互回调只触发一次明确操作，状态订阅只更新显示。
- 输入草稿不在每次 build 从外部值覆盖，避免坐标输入中途跳光标；仅在明确切换目标或重置时同步。

## 地图和平台能力门面

地图渲染器暂定 flutter_map。`MapCanvas` 是内部 Widget 门面，地图配置适配器处理瓦片源、归属、坐标转换及插件类型。地名搜索是独立服务，M1 默认不把公共地理编码接口当作无限免费后端。

会话命令统一经 `LocationSessionController → LocationSessionService → LocationSessionRepository → NativeLocationProvider → location_bridge`，不得在地图、按钮或页面中直接散落 MethodChannel 字符串。Repository 的实现协调 Native Provider；其纯接口和模型不依赖 GetX。Pigeon 与 Rust 的原始错误在边界转换，UI 不关心底层协议选择器。

界面预览可以使用明确标记的 Fake Repository，但不能把定时生成的“已连接/已修改”状态作为真实运行结果。生产配置默认使用真实能力探测；不支持时显示原因和可执行操作。

## 外观、可访问性和性能

- 通过 Theme/ColorScheme 和少量语义 token 管理样式，如 connected、pending、recovery；状态同时有文字和图标，不能只靠颜色。
- 适配 SafeArea、键盘、系统文字缩放与读屏标签；坐标显示仍有可朗读说明。按钮触控区域采用平台可访问性规范。
- 受网络影响的地图有加载/失败状态，失败后手工坐标输入仍可用。
- 地图、列表与状态卡分开订阅必要数据，避免每次心跳重建整张地图。只有需要时才采用性能优化，不提前引入缓存体系。
- 不用 silent audio 等后台保活技巧作为默认功能承诺，后台能力按真机证据展示。

组件测试聚焦坐标输入校验、异步按钮反馈、恢复入口、文字缩放和真实用户交互；不为只转发参数的低风险包装添加重复测试。
