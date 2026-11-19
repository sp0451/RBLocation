import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/session/session_snapshot.dart';
import '../../../routes/app_pages.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/inline_notice.dart';
import '../../../widgets/section_card.dart';
import '../controllers/location_workspace_controller.dart';
import '../widgets/coordinate_input.dart';
import '../widgets/location_action_bar.dart';
import '../widgets/session_status_card.dart';

class LocationWorkspaceView extends GetView<LocationWorkspaceController> {
  const LocationWorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CLocation',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            onPressed: () => Get.toNamed<void>(Routes.DEVICE_SETUP),
            tooltip: '设备准备',
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            8,
            AppSpacing.page,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkspaceHeading(controller: controller),
                  const SizedBox(height: 24),
                  Obx(() {
                    final snapshot = controller.snapshot;
                    final notices = <Widget>[];
                    if (!snapshot.capabilities.engineAvailable) {
                      notices.add(
                        InlineNotice(
                          title: '定位引擎尚未就绪',
                          message: '请先查看设备准备。能力检查通过前，设置位置与停止操作不可用。',
                          tone: NoticeTone.warning,
                          action: TextButton(
                            onPressed: () =>
                                Get.toNamed<void>(Routes.DEVICE_SETUP),
                            child: const Text('查看准备步骤'),
                          ),
                        ),
                      );
                    }
                    if (snapshot.recoveryRequired) {
                      notices.add(
                        const InlineNotice(
                          title: '需要确认定位恢复',
                          message:
                              '定位效果仍可能存在。请尝试停止模拟，并在系统地图中确认；连接断开不能证明真实定位已恢复。',
                          tone: NoticeTone.warning,
                        ),
                      );
                    }
                    if (controller.lastError != null) {
                      notices.add(
                        InlineNotice(
                          title: '操作未完成',
                          message: controller.lastError!.message,
                          tone: NoticeTone.error,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final notice in notices) ...[
                          notice,
                          const SizedBox(height: 16),
                        ],
                      ],
                    );
                  }),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final input = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CoordinateInput(
                            formKey: controller.formKey,
                            latitudeController: controller.latitudeController,
                            longitudeController: controller.longitudeController,
                            onPresetSelected: controller.selectPreset,
                            latitudeValidator: controller.validateLatitude,
                            longitudeValidator: controller.validateLongitude,
                            enabled: true,
                          ),
                          const SizedBox(height: 16),
                          Obx(
                            () => LocationActionBar(
                              canConnect: controller.canConnect,
                              canSet: controller.canSet,
                              canClear: controller.canClear,
                              isBusy: controller.isBusy,
                              onConnectRequested: controller.connect,
                              onSetRequested: controller.submitCoordinate,
                              onClearRequested: controller.clearSimulation,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '停止模拟会请求清除设置，不会将“断开连接”视为恢复成功。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      );
                      final status = Column(
                        children: [
                          Obx(() {
                            final snapshot = controller.snapshot;
                            return SessionStatusCard(
                              items: _statusItems(snapshot, controller.now),
                            );
                          }),
                          const SizedBox(height: 16),
                          _SessionDetails(controller: controller),
                        ],
                      );
                      if (constraints.maxWidth >= 800) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: input),
                            const SizedBox(width: 20),
                            Expanded(child: status),
                          ],
                        );
                      }
                      return Column(
                        children: [input, const SizedBox(height: 24), status],
                      );
                    },
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

class _WorkspaceHeading extends StatelessWidget {
  const _WorkspaceHeading({required this.controller});

  final LocationWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '定位实验工作区 · M0',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '选择位置，开始验证',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Obx(() {
          final capabilities = controller.snapshot.capabilities;
          final platform = switch (capabilities.platform) {
            RuntimePlatform.android => 'Android',
            RuntimePlatform.ios => 'iOS',
            RuntimePlatform.unsupported => '当前平台',
          };
          return Text(
            '$platform ${capabilities.osVersion} · 连接后手动提交位置，随后独立检查效果。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              height: 1.5,
            ),
          );
        }),
      ],
    );
  }
}

List<SessionStatusItem> _statusItems(SessionSnapshot snapshot, DateTime now) {
  final connection = switch (snapshot.connection) {
    SessionConnection.disconnected => '未连接',
    SessionConnection.connecting => '正在连接',
    SessionConnection.ready => '已连接',
    SessionConnection.lost => '连接已中断',
    SessionConnection.closing => '正在关闭连接',
  };
  final operation = snapshot.operation;
  final command = operation == null
      ? '尚无命令'
      : '${_operationName(operation.kind)} · ${_operationState(operation.state)}';
  final sample = snapshot.sample;
  final fresh = sample?.isFresh(now) ?? false;

  return [
    SessionStatusItem(
      title: '设备连接',
      value: connection,
      detail: snapshot.connection == SessionConnection.ready
          ? '连接可用；尚不能据此判断其他 App 的位置。'
          : '先完成设备准备，再发起连接。重连不会重放旧位置。',
      icon: Icons.link_rounded,
      highlighted: snapshot.connection == SessionConnection.ready,
    ),
    SessionStatusItem(
      title: '命令证据',
      value: command,
      detail: operation?.coordinate == null
          ? '服务回执与实际位置观测分别记录。'
          : '${operation!.coordinate!.label} · 仅为请求坐标。服务回执不能替代位置观测。',
      icon: Icons.receipt_long_outlined,
      highlighted: operation?.state == OperationState.acknowledged,
    ),
    SessionStatusItem(
      title: '位置观测',
      value: sample == null
          ? '尚无位置样本'
          : fresh
          ? '最近位置样本'
          : '位置样本已过期',
      detail: sample == null
          ? '请在系统地图或独立定位 App 中验证；未观测不等于已生效。'
          : '${sample.coordinate.label} · 精度 ${sample.accuracy.toStringAsFixed(0)} 米 · ${_localTime(sample.timestamp)} · ${switch (sample.isSimulated) {
              true => '模拟来源',
              false => '未标记为模拟',
              null => '来源未知',
            }}',
      icon: Icons.radar_rounded,
      highlighted: fresh,
    ),
  ];
}

String _operationName(OperationKind kind) => switch (kind) {
  OperationKind.connect => '连接',
  OperationKind.setLocation => '设置位置',
  OperationKind.clearLocation => '停止模拟',
  OperationKind.closeSession => '关闭连接',
  OperationKind.pairing => '设备配对',
};

String _operationState(OperationState state) => switch (state) {
  OperationState.pending => '处理中',
  OperationState.sent => '已发送（无服务确认）',
  OperationState.acknowledged => '服务已确认',
  OperationState.failed => '失败',
  OperationState.cancelled => '已取消',
  OperationState.indeterminate => '结果未知',
};

String _localTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

class _SessionDetails extends StatelessWidget {
  const _SessionDetails({required this.controller});

  final LocationWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          title: const Text('会话详情', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '查看当前会话的事件进度',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          children: [
            Obx(() {
              final snapshot = controller.snapshot;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailLine(label: '会话代次', value: '${snapshot.generation}'),
                  _DetailLine(label: '事件序号', value: '${snapshot.sequence}'),
                  _DetailLine(
                    label: '恢复要求',
                    value: snapshot.recoveryRequired ? '需要确认恢复' : '无待处理恢复要求',
                  ),
                  _DetailLine(
                    label: '最近命令',
                    value: snapshot.operation == null
                        ? '尚无'
                        : _localTime(snapshot.operation!.occurredAt),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '这里展示设备会话的最新已知状态。精确位置仅在工作区展示，不自动导出诊断。',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
