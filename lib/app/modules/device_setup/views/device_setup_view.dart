import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/session/session_snapshot.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/inline_notice.dart';
import '../../../widgets/section_card.dart';
import '../controllers/device_setup_controller.dart';
import '../widgets/pairing_interaction_pane.dart';
import '../widgets/prerequisite_checklist.dart';

class DeviceSetupView extends GetView<DeviceSetupController> {
  const DeviceSetupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备准备'),
        actions: [
          Obx(
            () => IconButton(
              onPressed: controller.isBusy
                  ? null
                  : controller.refreshPrerequisites,
              tooltip: '刷新检查',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '先准备，再连接',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '每项状态来自平台能力检查。未能确认的条件会保留为“待验证”。',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Obx(() {
                    final snapshot = controller.snapshot;
                    final capabilities = snapshot.capabilities;
                    final pairingPending =
                        snapshot.operation?.kind == OperationKind.pairing &&
                        snapshot.operation?.state == OperationState.pending;
                    final platform = switch (capabilities.platform) {
                      RuntimePlatform.android => 'Android',
                      RuntimePlatform.ios => 'iOS',
                      RuntimePlatform.unsupported => '未支持的平台',
                    };
                    return SectionCard(
                      title: '当前设备能力',
                      subtitle: '$platform ${capabilities.osVersion}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InlineNotice(
                            title: capabilities.engineAvailable
                                ? '定位引擎已接入'
                                : '定位引擎尚未接入',
                            message: capabilities.engineAvailable
                                ? '还需满足下方连接条件，并通过真机位置观测验证效果。'
                                : '当前构建不能在本平台设置模拟位置。可查看准备条件与具体原因，后续接入原生引擎后再验证。',
                            tone: capabilities.engineAvailable
                                ? NoticeTone.information
                                : NoticeTone.warning,
                          ),
                          if (capabilities.supportsPairing &&
                              !capabilities.isPaired &&
                              !pairingPending) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: controller.isBusy
                                  ? null
                                  : controller.startPairing,
                              icon: const Icon(Icons.phonelink_lock_rounded),
                              label: const Text('开始设备配对'),
                            ),
                          ],
                          if (pairingPending &&
                              controller.pairingPrompt == null) ...[
                            const SizedBox(height: 16),
                            InlineNotice(
                              title: '配对正在进行',
                              message:
                                  '系统配对流程仍在运行。临时配对码不会重放；可在系统设置中继续，或取消后重新开始。',
                              action: TextButton(
                                onPressed: controller.cancelPairing,
                                child: const Text('取消配对'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  Obx(() {
                    final failure = controller.lastError;
                    return failure == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: InlineNotice(
                              title: '准备操作未完成',
                              message: failure.message,
                              tone: NoticeTone.error,
                            ),
                          );
                  }),
                  Obx(() {
                    final prompt = controller.pairingPrompt;
                    if (prompt == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: PairingInteractionPane(
                        key: ValueKey(prompt.id),
                        title: prompt.title,
                        mode: switch (prompt.kind) {
                          PairingPromptKind.displayCode =>
                            PairingInteractionMode.displayCode,
                          PairingPromptKind.enterCode =>
                            PairingInteractionMode.enterCode,
                          PairingPromptKind.confirmOnDevice =>
                            PairingInteractionMode.confirmOnDevice,
                        },
                        displayCode: prompt.displayCode,
                        expirationLabel: _expirationLabel(
                          prompt.expiresAt,
                          controller.now,
                        ),
                        isExpired: !prompt.expiresAt.isAfter(controller.now),
                        onSubmitted: (code) =>
                            controller.submitPairing(prompt.id, code),
                        onCancelled: controller.cancelPairing,
                      ),
                    );
                  }),
                  Obx(
                    () => SectionCard(
                      title: '连接前检查',
                      subtitle: '完成系统操作后，返回此页刷新。',
                      child: PrerequisiteChecklist(
                        items: controller.snapshot.capabilities.prerequisites,
                        enabled: !controller.isBusy,
                        onActionRequested: controller.openSetup,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Obx(
                    () => FilledButton.icon(
                      onPressed: controller.isBusy
                          ? null
                          : controller.refreshPrerequisites,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('重新检查准备情况'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '设备连接、命令确认和定位效果将分别展示。完成准备后，请回到工作区手动连接。',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _expirationLabel(DateTime expiresAt, DateTime now) {
  final seconds = expiresAt.difference(now).inSeconds;
  return seconds <= 0 ? '此配对交互已过期，请重新发起。' : '此配对交互将在 $seconds 秒后过期。';
}
