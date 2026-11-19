import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/section_card.dart';

class SessionStatusItem {
  const SessionStatusItem({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    this.highlighted = false,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final bool highlighted;
}

/// Connection, command evidence and observations deliberately remain separate.
class SessionStatusCard extends StatelessWidget {
  const SessionStatusCard({required this.items, super.key});

  final List<SessionStatusItem> items;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '会话状态',
      subtitle: '分别查看连接、命令回执与位置观测。',
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index != 0) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
            ],
            _StatusRow(item: items[index]),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.item});

  final SessionStatusItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.highlighted ? AppColors.primary : AppColors.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: item.highlighted
                ? AppColors.primaryContainer
                : AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(item.icon, size: 21, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 3),
              Text(
                item.value,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                item.detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
