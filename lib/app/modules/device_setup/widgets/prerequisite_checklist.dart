import 'package:flutter/material.dart';

import '../../../data/models/session/session_snapshot.dart';
import '../../../theme/app_theme.dart';

class PrerequisiteChecklist extends StatelessWidget {
  const PrerequisiteChecklist({
    required this.items,
    required this.onActionRequested,
    required this.enabled,
    super.key,
  });

  final List<SessionPrerequisite> items;
  final ValueChanged<SetupTarget> onActionRequested;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        '暂未取得前置条件。请刷新检查结果。',
        style: TextStyle(color: AppColors.muted),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index != 0) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 18),
          ],
          _PrerequisiteRow(
            item: items[index],
            enabled: enabled,
            onActionRequested: onActionRequested,
          ),
        ],
      ],
    );
  }
}

class _PrerequisiteRow extends StatelessWidget {
  const _PrerequisiteRow({
    required this.item,
    required this.enabled,
    required this.onActionRequested,
  });

  final SessionPrerequisite item;
  final bool enabled;
  final ValueChanged<SetupTarget> onActionRequested;

  @override
  Widget build(BuildContext context) {
    final (color, icon, status) = switch (item.status) {
      PrerequisiteStatus.satisfied => (
        AppColors.primary,
        Icons.check_circle_outline_rounded,
        '已满足',
      ),
      PrerequisiteStatus.missing => (
        AppColors.warning,
        Icons.error_outline_rounded,
        '待完成',
      ),
      PrerequisiteStatus.unknown => (
        AppColors.muted,
        Icons.help_outline_rounded,
        '待验证',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$status${item.requiredForConnect ? ' · 连接必需' : ''}',
                style: TextStyle(color: color, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                item.detail,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (item.action != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: enabled
                      ? () => onActionRequested(item.action!)
                      : null,
                  child: Text(switch (item.action!) {
                    SetupTarget.developerSettings => '打开开发者设置',
                    SetupTarget.appSettings => '打开应用设置',
                    SetupTarget.locationSettings => '打开定位设置',
                    SetupTarget.locationPermission => '申请定位权限',
                    SetupTarget.notificationPermission => '申请通知权限',
                    SetupTarget.externalTunnel => '检查外部隧道',
                  }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
