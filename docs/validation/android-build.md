# Android 构建验证

验证日期：2026-10-20（Asia/Shanghai）。本记录只证明当前工作区的 Android 编译、原生单元测试及 Debug APK 组装通过，**未执行真机定位注入、其他 App 观测或恢复定位验收**。

后续通过 mobile_mcp 完成的单点定位和停止恢复验收另见 [Android 真机验证](2026-10-20-android-mock-location.md)，其中包含模拟应用声明修复及更新后的 APK 哈希。

## 日常 flutter run 的仓库修复

首次构建通过临时 init script 使用镜像，普通 `flutter run` 没有加载该脚本，仍会从不可达的 Google 仓库解析 AGP，出现 `com.android.application:9.0.1 not found`。该问题已通过项目配置修复：

- `android/settings.gradle.kts` 为插件解析优先配置阿里云 Google、Gradle Plugin 和公共 Maven 镜像。
- Flutter SDK 中的 Gradle included build 有独立仓库；在注册 includeBuild 前配置其仓库，覆盖 Kotlin 和构建工具依赖，不修改 Flutter SDK 文件。
- `android/build.gradle.kts` 为应用及插件依赖优先配置 Google、公共 Maven 和 Flutter 引擎镜像。
- 本地桥接插件的 buildscript 同步配置镜像，避免 AGP/Kotlin 类路径继续访问不可达仓库。
- 原有官方仓库作为后备保留，插件版本不变。`android/gradle.properties` 中 `clocation.useChinaMirrors=true` 控制镜像；可改为 `false` 仅使用标准仓库。

修复后的验证不传 `--init-script`：`flutter build apk --debug` 通过，`./gradlew help --offline --console=plain` 通过。随后在已连接的 SM G990U2 / Android 12（API 31）执行 `flutter run --debug --no-pub -d <device-id>`，Gradle 构建 14.9 秒、安装 4.2 秒，通过文件同步并建立 Dart VM Service。验证后脱离调试，保留应用运行；未发送定位模拟命令。Java 的 native-access warning 仍会出现，但不阻断运行。

## 首次构建结果与环境

- Gradle 9.1.0、Android Gradle Plugin 9.0.1、Kotlin 2.3.20、Java 21；Java/Kotlin 输出目标为 17。
- Android compileSdk / targetSdk 36、minSdk 24；宿主与本地插件均显式固定 `buildToolsVersion = "36.1.0"`。
- 本机已安装 Build Tools 36.1.0；未安装默认请求的 36.0.0。明确选择已安装版本后，避免了构建时自动下载缺失 SDK 工具。
- `:location_bridge:compileDebugKotlin`、`:location_bridge:testDebugUnitTest`、`:app:assembleDebug` 全部通过；最终输出 `BUILD SUCCESSFUL in 2m 54s`，84 个任务中 79 个执行、5 个已是最新。
- 原生 JUnit：7 项通过、0 项失败、0 项错误、0 项跳过。APK 构建期间宿主 Kotlin、Java、Manifest、Dex 与原生库合并也完成。

现有 Flutter / AGP 模板的兼容选项及 `Criteria` 旧平台适配仍产生弃用提示，不影响本轮构建；没有为消除提示升级或替换项目工具链。

## 首次临时镜像验证命令

工作目录：仓库下的 `android/`。

```sh
./gradlew :location_bridge:compileDebugKotlin \
  :location_bridge:testDebugUnitTest \
  :app:assembleDebug \
  --console=plain \
  --init-script /private/tmp/clocation-gradle-mirrors.init.gradle \
  -Dorg.gradle.internal.http.connectionTimeout=10000 \
  -Dorg.gradle.internal.http.socketTimeout=15000
```

本机直连 `dl.google.com:443` 超时；未带镜像的首次构建在解析 AGP 插件时失败，后续 SDK 自动下载也出现 SSL 握手失败。首次通过**仓库外的临时 Gradle init script** 验证，当时尚未将镜像接入项目。当前日常构建已采用上文的项目配置，不需要该临时脚本。

临时脚本内容如下；重现该网络环境时可保存到命令指定的路径。脚本只改变本次 Gradle 进程的仓库解析顺序及仓库偏好，不修改依赖坐标、版本、项目源码或 TLS 校验。

```groovy
gradle.beforeSettings { settings ->
    settings.dependencyResolutionManagement.repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    settings.pluginManagement.repositories {
        maven { url = uri('https://maven.aliyun.com/repository/google') }
        maven { url = uri('https://maven.aliyun.com/repository/gradle-plugin') }
        maven { url = uri('https://maven.aliyun.com/repository/public') }
    }
    settings.dependencyResolutionManagement.repositories {
        maven { url = uri('https://maven.aliyun.com/repository/google') }
        maven { url = uri('https://maven.aliyun.com/repository/public') }
        maven { url = uri('https://storage.flutter-io.cn/download.flutter.io') }
    }
}
gradle.beforeProject { project ->
    project.buildscript.repositories {
        maven { url = uri('https://maven.aliyun.com/repository/google') }
        maven { url = uri('https://maven.aliyun.com/repository/public') }
        maven { url = uri('https://maven.aliyun.com/repository/gradle-plugin') }
    }
}
```

镜像来源：[阿里云 Maven 仓库](https://maven.aliyun.com/)（Google、Gradle Plugin 与公共 Maven 镜像）、[Flutter 中国网络镜像说明](https://docs.flutter.dev/community/china)。这项网络构建验证不等同于验证镜像与所有上游仓库内容永久一致，也不构成项目发布仓库配置的变更。

## 原生测试证据

| 测试 | 验证点 | 结果 |
| --- | --- | --- |
| `NativeCommandGateTest.stopInvalidatesInflightSetAndBlocksNewSetUntilCleanup` | 停止使旧设置失效，并在清理期间拒绝新设置 | 通过 |
| `NativeCommandGateTest.newestPendingSetWins` | 新的待处理设置替换旧设置 | 通过 |
| `NativeCommandGateTest.coordinatesRejectNonfiniteAndOutOfRangeValues` | 拒绝 NaN、无穷值与越界 WGS84 坐标 | 通过 |
| `NativeProviderLeaseTest.enableFailureStillReleasesProviderWhoseAddSucceeded` | provider 添加后启用失败，仍可清理已添加资源 | 通过 |
| `NativeProviderLeaseTest.cleanupContinuesAfterFailureAndRetryAcquiresMissingProvider` | 一个 provider 清理失败时继续处理另一个，重试补齐缺失资源 | 通过 |
| `NativeProviderLeaseTest.freshProcessRecoveryRemovesKnownProvidersWithoutAcquiringThem` | 新进程恢复只清除已知 provider，不重放设置 | 通过 |
| `NativeProviderLeaseTest.uncertainAddIsCleanedEvenWhenCallDidNotReturnToTrackOwnership` | 系统已变更但 binder 回执丢失时，恢复清理仍覆盖未记录资源 | 通过 |

机器生成的完整结果位于：

- `build/location_bridge/test-results/testDebugUnitTest/TEST-com.clocation.location_bridge.NativeCommandGateTest.xml`：tests=3、failures=0、errors=0。
- `build/location_bridge/test-results/testDebugUnitTest/TEST-com.clocation.location_bridge.NativeProviderLeaseTest.xml`：tests=4、failures=0、errors=0。
- `build/location_bridge/reports/tests/testDebugUnitTest/index.html`：HTML 测试报告。

这些是纯逻辑资源管理和停止屏障测试，不涉及真实手机的权限交互、前台服务生存时间或定位样本。

## APK 产物

- Flutter 输出：`build/app/outputs/flutter-apk/app-debug.apk`，约 140 MiB。
- Android 输出：`build/app/outputs/apk/debug/app-debug.apk`。
- 首次构建 Flutter 输出的 SHA-256：`e3de5ef9e3796477d6a7b60f934da7700da69bb267727551bd417cb95d32b6a2`；后续真机修复版本的哈希见上面的真机记录。

该文件为当前工作区生成的 Debug APK，使用开发调试签名。后续源码变化、重新打包或签名变化会改变校验值；构建产物不进入版本库。
