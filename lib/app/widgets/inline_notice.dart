import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum NoticeTone { information, warning, error }

class InlineNotice extends StatelessWidget {
  const InlineNotice({
    required this.title,
    required this.message,
    this.tone = NoticeTone.information,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (tone) {
      NoticeTone.information => (
        AppColors.primaryContainer,
        AppColors.primary,
        Icons.info_outline_rounded,
      ),
      NoticeTone.warning => (
        AppColors.warningContainer,
        AppColors.warning,
        Icons.warning_amber_rounded,
      ),
      NoticeTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    height: 1.5,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
