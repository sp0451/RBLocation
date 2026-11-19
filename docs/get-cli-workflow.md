# Get CLI 工程工作流

本项目按用户要求，使用 **get_cli 1.9.1** 创建项目与页面，选择 **GetX Pattern (by Kauê)**。运行时状态、依赖注入与路由固定使用 `get: ^4.7.3`，不采用 CLEAN 模板。

## 新工程与页面

```sh
dart pub global activate get_cli 1.9.1
get create project:clocation
```

交互选择 Flutter Project，组织域名 `com.clocation`，Swift、Kotlin，启用 linter，架构选 GetX Pattern。CLI 初始化时会覆盖新工程的演示 `lib`，不能对含业务代码的工程无备份执行 `get init`。

在项目根目录生成页面：

```sh
get create page:startup
get create page:location_workspace
get create page:device_setup
```

新增后续功能仍使用 `get create page:<snake_case_name>`，再补充业务实现与构造注入。生成器负责模块目录和路由登记；删除演示页面时同时清理路由、导入和空目录。

## 必须保持的规范

- 模块目录：`lib/app/modules/<module>/{bindings,controllers,views}`，内部业务组件放 `widgets`。
- 页面 View 继承 `GetView<Controller>`，页面 Controller 由模块 Binding 用 `Get.lazyPut` 装配。
- `app_pages.dart` 包含 `part 'app_routes.dart'`、`GetPage` 与页面 Binding；`app_routes.dart` 使用 `part of`。
- 路由沿用 CLI 的 `Routes.STARTUP`、`Routes.LOCATION_WORKSPACE`、`Routes.DEVICE_SETUP` 等大写常量。导航导入 `app_pages.dart`，不单独 import part 文件。
- `AppPages.INITIAL = Routes.STARTUP`，入口采用 `GetMaterialApp`；应用 Repository 和常驻 GetxService 由 `InitialBinding` 装配。
- 生成后删除计数器与空生命周期演示代码；页面释放不停止原生会话。服务、模型、数据源按项目职责扩展，不预建空分层。

## 本轮创建记录

已实际运行 `get_cli 1.9.1` 的 `create project:clocation` 和上述三个 `create page` 命令。为保留已写好的双端原生实现和 Flutter 功能代码，先备份 `lib`，在临时目录生成完整项目，再将 CLI 生成的入口、模块骨架和路由迁入当前仓库，恢复功能实现并移除默认 Home 演示页。保留了原生桥接、签名宿主配置及现有依赖约束。

本轮 CLI 安装使用隔离的临时 PUB_CACHE，不依赖把生成目录加入项目；开发机常规安装按上面的命令执行。没有修改 CLI 源码或模板。此记录说明工程来源，后续开发以当前仓库文件为准。

来源：[Get CLI 官方项目](https://github.com/jonataslaw/get_cli)、[1.9.1 发布包](https://pub.dev/packages/get_cli/versions/1.9.1)。
