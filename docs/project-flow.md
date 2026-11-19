# 项目流程图

本页描述目标设计，尚未实现或完成真机验证。状态管理、依赖装配与路由使用 `get: ^4.7.3`；目录参照 [目录结构与文件分类](directory-structure.md)。状态和资源语义以 [项目架构](architecture.md) 为准，跨层消息见 [时序图](sequence-diagrams.md)，文档入口见 [开发文档总览](README.md)。

可缩放导出见 [SVG 图示预览](diagrams/README.md)。本页 Mermaid 代码块为可编辑源，更新后同步重新导出。

## 应用启动与平台准备

`InitialBinding.dependencies()` 同步注册依赖，`LocationSessionService.onInit()` 启动受管异步初始化；初始化失败进入可重试错误态，不能让未捕获的异步错误逃逸。初始化和设备连接是不同步骤，首屏无需等待用户完成配对或系统设置。

```mermaid
flowchart TD
  appStart["启动 GetMaterialApp"] --> initialBinding["InitialBinding 同步注册 Repository 和常驻 LocationSessionService"]
  initialBinding --> serviceInit["Service 启动受管异步 attach 并显示 loading"]
  initialBinding --> routeBinding["当前 GetPage 的 Binding 注册页面 Controller"]
  routeBinding --> viewLoading["View 读取只读状态，未 ready 时禁用位置操作"]
  serviceInit --> snapshotSync["原生原子返回快照，合并水位之后的缓存事件"]
  snapshotSync --> syncReady{"快照同步成功？"}
  syncReady -->|"否"| initError["显示初始化错误和重试入口"]
  initError -->|"用户重试"| serviceInit
  syncReady -->|"是"| capabilities["显示真实能力和前置条件检查结果"]
  capabilities --> platform{"运行平台？"}
  platform -->|"iOS"| iosSetup["检查开发者模式、设备准备、本机配对及外部 LocalDevVPN"]
  platform -->|"Android"| androidSetup["检查系统定位、必要权限、模拟应用授权及前台服务条件"]
  iosSetup --> setupReady{"前置条件满足？"}
  androidSetup --> setupReady
  setupReady -->|"缺失或未知"| setupGuide["给出具体引导并重新检测，不宣称定位能力可用"]
  setupGuide --> capabilities
  setupReady -->|"是，用户请求连接"| nativeConnect["原生建立平台定位服务会话"]
  nativeConnect --> connectionReady{"服务握手成功？"}
  connectionReady -->|"否"| connectionError["显示结构化错误与恢复入口"]
  connectionError --> capabilities
  connectionReady -->|"是"| ready["connectionState 为 ready，允许提交设置"]
```

iOS 的隧道连通、本机配对和开发者服务握手分别检测；VPN 图标本身不是定位证据。配对交互角色由 M0 接入所选协议后确定。页面返回或切换路由只销毁页面 Controller 及其 UI 订阅，不清除常驻服务或原生会话。

## 单点设置、观测与恢复

设置意图、命令发送/确认和位置观测分开显示；即使命令已确认，本 App 或第三方 App 的实际位置仍需独立观察。

```mermaid
flowchart TD
  selectPoint["手输或地图选择坐标"] --> validatePoint{"WGS84 坐标合法？"}
  validatePoint -->|"否"| inputError["保留输入并显示校验错误"]
  inputError --> selectPoint
  validatePoint -->|"是"| submitSet["用户提交设置请求和独立 operationId"]
  submitSet --> nativeGate{"连接可用且未处于停止屏障？"}
  nativeGate -->|"否"| rejectSet["返回未连接或 operationInProgress"]
  nativeGate -->|"是"| setQueue["串行执行，尚未发送的坐标更新合并为最近一次"]
  setQueue --> setResult["记录命令结果：sent、可得的 acknowledged 或失败/不明"]
  setResult --> showEvidence["显示命令证据，独立更新新鲜定位样本"]
  showEvidence --> chooseAction{"下一步操作？"}
  chooseAction -->|"重新选点"| selectPoint
  chooseAction -->|"停止或正常关闭连接"| stopBarrier["设置停止屏障，移除待发设置并使旧结果失效"]
  stopBarrier --> activeRequest["让在途请求安全结束；超时则失效并关闭底层请求"]
  activeRequest --> canClear{"当前连接能否清除？"}
  canClear -->|"是"| clearRequest["发清除请求，分别记录发送、确认或失败证据"]
  clearRequest --> boundedObserve["有限等待恢复观测，M0 暂定最多 15 秒"]
  boundedObserve --> releaseResources["记录观测结果并释放会话资源"]
  canClear -->|"否"| unknownRecovery["保留 recoveryRequired，提供恢复连接后重试清除"]
  releaseResources --> recoveryEvidence{"清除与观测证据是否充分？"}
  recoveryEvidence -->|"否或不明"| unknownRecovery
  recoveryEvidence -->|"是"| observedRecovery["仅说明本 App 的恢复观测；目标 App 单独验收"]
  unknownRecovery --> userRecovery["用户显式发起恢复连接与清除"]
  userRecovery --> stopBarrier
```

清除期间的新设置返回 `operationInProgress`，清除流程终结后须由用户重新提交。停止不是简单地取消 Dart Future；底层在途设置不得在停止之后继续覆盖位置。清除失败、观测超时、权限不足分别记录，等待观测不得永久阻塞资源释放。

断连或进程被强退后，定位效果可为 `unknown`，新进程的 `disconnected` 不能证明已恢复。重连只恢复通信和同步快照，不自动重放历史设置；必要时显示恢复提示并由用户显式清除。

## 开发阶段与出口

```mermaid
flowchart LR
  stageZero["M0：类型化桥接、能力检测、单点设置与停止"] --> evidenceGate{"每个平台分别取得真机设置、观测和清除证据？"}
  evidenceGate -->|"失败或未验证"| experimental["标记该平台实验状态并修复失败路径"]
  experimental --> stageZero
  evidenceGate -->|"已验证的平台"| stageOne["M1：地图、收藏、偏好、诊断及日常测试流程"]
  stageOne --> scenarioGate{"前后台、锁屏、网络切换及恢复是否达到验收要求？"}
  scenarioGate -->|"否"| stageOne
  scenarioGate -->|"是"| stageTwo["M2：按需交付 GPX、路线播放、速度和摇杆"]
```

GetX 的应用装配和页面 Binding 随实际需要引入；M0 最小验证可只保留必要页面，不为路线或收藏预建空模块。每阶段的详细范围、证据等级和记录字段见 [开发阶段与验收](development-roadmap.md)。
