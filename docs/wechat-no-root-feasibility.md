# 当前三星免 Root 的微信定位替代方案

研究日期：2026-10-21。用户已明确：只考虑当前 Samsung SM-G990U2，免 Root。本页是选型研究，不代表已接入框架或通过微信验收。

## 结论与范围

当前标准模拟位置已影响 Google Maps，但微信 8.0.79 的位置选择页仍显示实际区域，见 [同机复核](validation/2026-10-21-android-wechat-compatibility.md)。继续增加普通权限、改坐标系或接入另一套 mock API，没有证据能解决这一差异。

免 Root 仍有两个可研究方向：**修改目标 APK 后在应用内加载框架**，或**让目标应用运行在虚拟容器内**。二者改变目标应用的运行方式，不能由 CLocation 直接接管系统中未修改、未加载进容器的官方微信。目前未找到本机、本系统与微信 8.0.79 组合的可靠通过记录。

若要求同时满足“当前手机、免 Root、保持原有官方微信安装和运行方式”，本轮没有找到可确认交付的通用定位改写方案。这是当前证据的边界，不是对所有未来实现的绝对判断。

## 设备条件与已知证据

本轮通过只读 ADB 获取：Android 12，`ro.boot.flash.locked=1`、`ro.boot.vbmeta.device_state=locked`、`ro.boot.verifiedbootstate=green`。`ro.oem_unlock_supported` 为空，不能据此认定永远不能解锁。没有执行重启、解锁、刷机或安装替代框架。

系统分发 mock 回调不等于微信接受该回调；闭源微信究竟采用 mock 过滤、网络定位或缓存，尚未确定。本轮没有更改手机模拟坐标、微信安装或网络设置。

## 候选比较

| 方案 | 免 Root | 影响范围 | 本轮结论 |
| --- | --- | --- | --- |
| 既有系统 test provider | 是 | 接受系统 mock 数据的应用 | Maps 已通过，微信本次未生效 |
| Google FLP mock API | 是 | 使用 FLP 的客户端 | 官方明确结果带 mock 标记，不能承诺解决微信 |
| Shizuku / ADB 辅助 | 是，使用 shell 身份时 | shell 权限允许的操作 | 可辅助安装、授权；没有证据能独立强制原有微信采用坐标 |
| JingMatrix/LSPatch | 是 | 被修改并加载框架的目标 APK | 首个技术原型候选；本机微信兼容性未知 |
| VirtualApp 类容器 | 是 | 在容器内运行的应用 | 第二候选；Android 12、arm64 和新版微信需重新验证 |
| Root + 系统框架模块 | 否 | 视实现为系统或指定应用 | 不符合用户当前约束，不进入实施计划 |

Google 的 `setMockLocation` 文档明确说明发给 FLP 客户端的位置会标记为 mock。因此新增 GMS 依赖不等于消除来源识别。[Google FLP 文档](https://developers.google.com/android/reference/com/google/android/gms/location/FusedLocationProviderClient)

Shizuku 官方区分 root UID 0 与 ADB UID 2000；权限仍受 Android、Linux 和 SELinux 约束。由此推断，接入 Shizuku 本身不是跨进程改写任意应用定位的完整方案。[Shizuku API 开发说明](https://github.com/RikkaApps/Shizuku-API)

## 候选一：应用内加载框架

[JingMatrix/LSPatch](https://github.com/JingMatrix/LSPatch) 当前说明：通过修改目标 APK 嵌入框架，免 Root；最低 Android 9；只能作用于已修改的目标，不能处理系统进程或其他未修改应用。Android 12 满足其声明的最低版本，仍不足以证明三星 ROM 或微信可用。其 Shizuku 集成用于辅助安装，不是系统定位改写能力。

它是框架，不是现成的微信定位插件。需要另外开发或核实定位模块、配置通信、各应用进程加载与停止恢复；SDK 自有位置对象或网络结果是否覆盖，要靠目标版本实测。[旧 LSPosed/LSPatch](https://github.com/LSPosed/LSPatch) 已归档，不能把旧版或 Root 模块兼容性直接套用到这个分支。

APK 修改通常涉及重新签名。我们没有微信官方签名密钥，不能假定可作为普通更新覆盖现有安装，也不能承诺聊天数据、登录和后续官方升级兼容。改包名并不能自动解决这些问题。[Android 应用签名说明](https://developer.android.com/studio/publish/app-signing)

项目 LICENSE 为 GPL v3；若选定接入，须固定源码提交、构建输入、产物哈希与依赖许可，再决定分发方式。本轮未下载或执行框架安装包，也未对微信进行打包修改。[LSPatch LICENSE](https://github.com/JingMatrix/LSPatch/blob/master/LICENSE)

## 候选二：虚拟容器

[VirtualApp](https://github.com/asLody/VirtualApp) 的原理是在宿主内代理目标应用的系统交互。只有容器里的实例受到影响，原有微信不会因此改变。作者说明 GitHub 源码停止更新于 2017 年 12 月，后续商业版本另行维护；仓库展示的现代系统适配记录不能视作公开代码的能力。

[VirtualLocation](https://github.com/pengliangAndroid/VirtualLocation) 是这一路线的公开参考，README 声称支持微信，但同时指出 GPS 转 Wi-Fi 接口不可用和底层使用授权限制。没有本机微信 8.0.79 的通过证据，不能直接选作可交付依赖。

容器路线的先决条件包括 Android 12 / arm64 运行、多进程、地图页、权限、系统组件交互、登录及生命周期兼容。应先用自有测试应用验证运行与定位，再决定是否做微信测试；不得仅凭旧截图宣布成功。

## 排除与旁证

Root 路线确有公开项目，例如 [GPS Setter](https://github.com/varma322/android-gps-setter) 和 [AnyDoor](https://github.com/zhaoyuxiangyyds-lab/AnyDoor)，但不符合本轮范围。项目自述不是微信实测，不能作为成功保证。另一个常见搜索结果 [LocationSpoofer 原仓库](https://github.com/HuangZhuoRui/LocationSpoofer) 已于 2026-10-18 归档，目前只保留说明与许可；旧搜索摘要中的功能介绍不代表当前仍提供源码或安装包。

VPN/IP 切换、地图中心移动和在微信手动搜索地点，都不能证明系统定位或微信“我的位置”已经改变。iPhone 开发者服务路线继续保留既有实现状态，但不属于用户此次限定的三星免 Root 方案。

## 建议的验证顺序与退出条件

1. **先验证框架能力。** 若允许研究应用内加载，使用独立包名、可重新签名的自有测试 App，在本机验证加载、坐标 A/B、进程重启、停止恢复和配置隔离。此步骤不触碰原有微信。
2. **再选择目标运行方式。** 明确是否接受修改 APK 或容器内运行。若必须保持原有官方微信运行方式，则停止这两条路线，不把原型包装为系统级方案。
3. **单独进行微信验收。** 仅在可保留原有安装与数据的测试安排确定后，检查位置选择页的初次打开、重新定位、切前后台和重启。发送位置、实时共享和小程序分别验收，不从某一个页面推断全部支持。
4. **坐标 A → B → 停止。** 系统观察、自有 App 观察、微信地图和附近地点分别记录；地图展示转换与 WGS84 引擎输入分开处理。停止后的真实样本需为停止之后的新样本。
5. **失败即限定结论。** 不能加载、不能独立安装、登录或地图不可用、停止后无法恢复，任一项失败均不进入产品集成。没有独立观察证据时保持“未验证”。

此次仅有研究与只读设备检查，没有执行上述新路线的原型或微信测试。仓库不保存真实精确坐标、聊天内容或设备序列号。

## 对 CLocation 的影响

当前 Get CLI / GetX Pattern、`get: ^4.7.3`、LocationSessionService 和标准 Android 引擎保持现状。不提前加入 LSPatch、VirtualApp、Shizuku 或 Root 依赖。

若原型通过，再制定独立原生适配方案：显式区分“系统模拟”和“仅指定测试实例”，原生层拥有能力探测与停止屏障，Flutter 展示实际作用范围。不要让 UI 显示“系统定位已修改”来描述容器或应用内效果，也不要在微信升级后沿用旧版通过结论。
