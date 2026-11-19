# 项目时序图

以下为目标设计，不表示已有接口实现或真机能力。所有图使用本地 Markdown Mermaid，可随代码评审同步维护；[项目流程图](project-flow.md) 展示完整业务路径，[项目架构](architecture.md) 定义接口、状态及资源约束，[目录规范](directory-structure.md) 定义文件归属，[文档总览](README.md) 为统一入口。

可缩放导出见 [SVG 图示预览](diagrams/README.md)。本页 Mermaid 代码块为可编辑源，更新后同步重新导出。

`LocationSessionService extends GetxService` 是应用级常驻会话门面，包裹 Repository 并提供只读 Rx 快照及操作。页面 Controller 由对应 `GetPage` 的 Binding 注册，并通过构造参数接收服务。后续图为保持可读性，服务与原生间的箭头省略 Repository、插件门面和 Pigeon 逐层转发；这些层仍遵守架构文档的依赖方向。

## 启动注册、快照与事件同步

`Bindings.dependencies()` 保持同步；服务在 `onInit()` 启动带错误处理、可重试的受管异步任务。View 在同步成功前保持 loading/error，不能提交位置操作。常驻服务只注册一次，页面销毁不停止原生会话。

```mermaid
sequenceDiagram
  participant app as GetMaterialApp
  participant initialBinding as InitialBinding
  participant routeBinding as 当前路由 Binding
  participant controller as 页面 GetxController
  participant sessionService as 应用会话服务
  participant repository as LocationSessionRepository
  participant bridge as locationBridge
  participant nativeSession as 原生串行会话
  app->>initialBinding: 调用同步 dependencies()
  initialBinding->>repository: 创建 Repository 实现及原生适配器
  initialBinding->>sessionService: 注入 Repository 并 permanent 注册
  sessionService->>sessionService: onInit 启动受管异步初始化
  app->>routeBinding: 进入 GetPage
  routeBinding->>routeBinding: lazyPut 只注册 Controller 工厂
  app->>controller: GetView 首次读取 Controller 时触发工厂并注入 Service
  controller->>sessionService: 读取只读 Rx 状态并显示 loading
  sessionService->>repository: 初始化事件投影
  repository->>bridge: 安装普通事件回调并开启临时缓冲
  bridge->>nativeSession: attach()
  nativeSession->>nativeSession: 同一串行上下文注册接收端并获取原子快照
  nativeSession-->>bridge: 普通事件可能先于返回到达
  bridge-->>repository: 暂存事件，不提前覆盖状态
  nativeSession-->>bridge: 返回包含 runtimeId 和 sequence 水位的快照
  bridge-->>repository: 返回快照
  repository->>repository: 先应用快照，再处理同实例且高于水位的事件
  alt 事件连续且会话匹配
    repository-->>sessionService: 发布有序领域快照
    sessionService-->>controller: ready 状态及独立能力检查结果
  else 实例更换、序号缺口或未知会话
    repository->>bridge: getSnapshot() 重新同步
    bridge->>nativeSession: 请求最新原子快照
    nativeSession-->>repository: 经桥接返回快照或结构化错误
    repository-->>sessionService: 更新快照或可重试错误态
  end
  controller->>controller: onClose 释放 UI workers 和订阅
```

配对交互不进入上述普通事件缓冲，不参与历史重放。实际实现中，所有跨层返回仍按桥接路径传递；图中的合并返回箭头仅用于省略转发。

## iOS 配对与连接

首期复用外部 LocalDevVPN。验证码由哪一端显示、输入或确认，取决于选定协议的实际握手角色；图只表达一次性类型化交互，不预设 PIN 方向。临时验证码退出即清空，密钥和完整配对记录始终留在原生层。

```mermaid
sequenceDiagram
  participant user as 用户
  participant controller as 配对页面 Controller
  participant sessionService as 应用会话服务
  participant nativeSession as Swift 会话
  participant tunnel as 外部 LocalDevVPN
  participant protocolService as idevice 开发者服务
  participant keychain as Keychain
  controller->>sessionService: 检测能力与前置条件
  sessionService->>nativeSession: getCapabilities()
  nativeSession->>tunnel: 检查外部隧道可达性和目标身份
  nativeSession-->>controller: 经 Service 返回 satisfied、missing 或 unknown
  user->>controller: 完成必要准备并发起配对
  controller->>sessionService: startPairing()
  sessionService->>nativeSession: 启动有效配对流程
  nativeSession->>protocolService: 按选定协议执行握手
  opt 握手需要用户交互
    protocolService-->>nativeSession: 请求所需类型化交互
    nativeSession-->>controller: 经独立回调传递一次性交互
    controller->>user: 按实际角色显示、输入或确认
    user->>controller: 完成交互或取消
    controller->>nativeSession: 经 Service 回应当前交互或取消配对
    nativeSession->>protocolService: 处理协议交互或结束握手
  end
  alt 配对成功
    protocolService-->>nativeSession: 原生层收到配对记录
    nativeSession->>keychain: 保存受保护配对凭据
    nativeSession-->>sessionService: 配对状态，不含凭据
    user->>controller: 请求连接
    controller->>sessionService: connect()
    sessionService->>nativeSession: 建立定位开发者服务会话
    nativeSession->>protocolService: 经外部隧道握手并打开定位服务
    protocolService-->>nativeSession: 返回服务可用性结果
    nativeSession-->>sessionService: 发布 ready 或结构化失败
  else 取消、超时或握手失败
    nativeSession->>nativeSession: 销毁临时交互并释放配对资源
    nativeSession-->>sessionService: 发布取消或失败状态
  end
```

`ready` 只表示服务可调用。连接操作不重放旧的 `setLocation`；检测到上次未完成变更时保留恢复入口，提示用户显式清除。

## 设置坐标与独立定位观测

命令与样本在原生层有序发布，Repository 用 `runtimeId`、`sessionId`、`generation`、`sequence` 和 `operationId` 防止旧结果覆盖当前状态。桥接返回无错误不能自动等同于协议确认。

```mermaid
sequenceDiagram
  participant user as 用户
  participant controller as 定位页面 Controller
  participant sessionService as 应用会话服务
  participant nativeSession as 原生串行会话
  participant platformRuntime as 平台定位运行时
  participant observation as 本 App 定位观测源
  user->>controller: 确认已校验的 WGS84 坐标
  controller->>sessionService: setLocation(operationId, coordinate)
  sessionService->>nativeSession: 提交类型化设置请求
  nativeSession->>nativeSession: 检查坐标、连接、权限及停止屏障
  alt 当前允许设置
    nativeSession->>nativeSession: 合并待发设置并串行执行
    nativeSession->>platformRuntime: 写入当前设置命令
    alt 仅能证明写出
      platformRuntime-->>nativeSession: 发送结果
      nativeSession-->>sessionService: commandState 为 sent
    else 协议确有服务回执
      platformRuntime-->>nativeSession: 实际协议确认
      nativeSession-->>sessionService: commandState 为 acknowledged
    else 发送失败或结果不明
      platformRuntime-->>nativeSession: 失败或超时
      nativeSession-->>sessionService: failed 或 indeterminate 及恢复要求
    end
    sessionService-->>controller: 分别显示请求坐标和命令证据
  else 未连接、授权不足或正在停止
    nativeSession-->>sessionService: 结构化拒绝，不执行注入
    sessionService-->>controller: 显示错误和可行操作
  end
  observation-->>nativeSession: 独立定位样本及时间、精度和可用模拟标记
  nativeSession-->>sessionService: 带水位的样本事件
  sessionService-->>controller: 独立显示 observationState 和样本新鲜度
```

本 App 样本不能证明所有 App 已采用该位置。Apple Maps、独立 Core Location 测试 App 及用户关心的目标 App，按 [验收计划](development-roadmap.md) 分别记录实际行为。

## 停止优先、清除与有界恢复观测

停止必须先阻断旧设置继续生效。已经发出的请求能取消则取消，不能取消则等待其安全结束；超时必须失效或关闭底层请求，不能只让 Dart 等待结束。清除全流程受停止屏障保护。

```mermaid
sequenceDiagram
  participant controller as 页面 Controller
  participant sessionService as 应用会话服务
  participant nativeSession as 原生串行会话
  participant platformRuntime as 平台定位运行时
  participant observation as 本 App 定位观测源
  controller->>sessionService: 用户停止或正常关闭连接
  sessionService->>nativeSession: clearLocation(newOperationId)
  nativeSession->>nativeSession: 设置停止屏障并使旧设置结果失效
  nativeSession->>nativeSession: 删除待发设置，取消或有界等待在途设置
  controller->>sessionService: 清除期间提交新设置
  sessionService->>nativeSession: setLocation(otherOperationId, coordinate)
  nativeSession-->>sessionService: operationInProgress
  alt 底层请求已安全结束且连接可用
    nativeSession->>platformRuntime: 发送清除命令
    platformRuntime-->>nativeSession: sent、可得的 acknowledged、失败或不明
    nativeSession->>nativeSession: 记录清除证据，失败或不明保留恢复要求
    nativeSession->>observation: 等待后续新鲜样本，M0 上限暂定 15 秒
    alt 收到可判读的新样本
      observation-->>nativeSession: 返回样本及可用来源信息
      nativeSession->>nativeSession: 独立记录本 App 恢复观测结果
    else 超时、权限不足或没有可判读样本
      observation-->>nativeSession: 恢复观测未确认
      nativeSession->>nativeSession: 保留命令证据与恢复提示
    end
  else 请求无法继续或连接已失效
    nativeSession->>nativeSession: 失效并关闭底层请求，保留 recoveryRequired
  end
  nativeSession->>nativeSession: 释放会话资源，清除流程终结后解除停止屏障
  nativeSession-->>sessionService: 发布命令、观测及恢复要求的最终快照
  sessionService-->>controller: 显示各项证据与必要的恢复入口
```

恢复连接后只能显式重试清除，不能重放旧设置。强退无法保证本图执行，新进程必须把定位效果当作未知；受保护的未完成记录只用于恢复提示，不作为当前原生连接的证据。

## Android 前台服务、注入与停止通知

模拟应用授权、必要定位权限、系统定位和当前 Android 版本的前台服务条件均由原生校验。原生前台服务拥有 provider 和注入循环；Flutter 页面不负责用定时器维持定位。

```mermaid
sequenceDiagram
  participant sessionService as 应用会话服务
  participant nativeSession as Kotlin 会话
  participant foregroundService as 定位前台服务
  participant androidSystem as Android 系统定位
  participant notification as 系统停止通知
  sessionService->>nativeSession: 连接并提交坐标设置
  nativeSession->>androidSystem: 检查系统定位、权限、模拟应用和前台服务条件
  androidSystem-->>nativeSession: 当前授权与系统状态
  alt 前置条件不足
    nativeSession-->>sessionService: 返回结构化错误和设置引导
  else 前置条件满足
    nativeSession->>foregroundService: 启动原生前台会话
    foregroundService->>notification: 展示持续通知及停止操作
    foregroundService->>androidSystem: 创建受控测试 provider
    loop 原生会话有效且未进入停止屏障
      foregroundService->>androidSystem: 按原生节奏注入当前坐标
      androidSystem-->>foregroundService: 平台调用结果，按可得证据归类
      foregroundService-->>nativeSession: 发布命令和资源状态
      nativeSession-->>sessionService: 带水位的状态快照或事件
    end
    notification->>foregroundService: 用户点击停止
    foregroundService->>nativeSession: 请求统一停止流程
    nativeSession->>nativeSession: 设置停止屏障并使旧设置失效
    nativeSession->>foregroundService: 终止注入循环并移除测试 provider
    foregroundService->>androidSystem: 执行 provider 清理
    androidSystem-->>foregroundService: 清理结果
    foregroundService->>foregroundService: 有界记录后续观测并释放前台资源
    foregroundService->>notification: 移除持续通知
    foregroundService-->>nativeSession: 清除、观测和资源释放结果
    nativeSession-->>sessionService: 发布最终快照与必要恢复要求
  end
```

循环中的权限撤销或 provider 错误也必须进入结构化失败与统一清理路径。App 内停止与通知停止共用原生入口；即使 Dart 事件接收端已解除，通知停止仍能触发资源清理。清除证据、后续位置样本和目标 App 验收仍分别记录。
