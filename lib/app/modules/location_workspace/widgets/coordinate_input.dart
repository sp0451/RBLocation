import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/section_card.dart';

class CoordinateInput extends StatelessWidget {
  const CoordinateInput({
    required this.formKey,
    required this.latitudeController,
    required this.longitudeController,
    required this.onPresetSelected,
    required this.latitudeValidator,
    required this.longitudeValidator,
    required this.enabled,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final void Function(double latitude, double longitude) onPresetSelected;
  final FormFieldValidator<String> latitudeValidator;
  final FormFieldValidator<String> longitudeValidator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '目标位置',
      subtitle: '输入 WGS84 坐标；选择位置后，点击“设置位置”才会提交。',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'WGS84',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.muted,
            letterSpacing: 0.7,
          ),
        ),
      ),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: latitudeController,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textInputAction: TextInputAction.next,
              validator: latitudeValidator,
              decoration: const InputDecoration(
                labelText: '纬度',
                hintText: '−90 至 90',
                suffixText: '°',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: longitudeController,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textInputAction: TextInputAction.done,
              validator: longitudeValidator,
              decoration: const InputDecoration(
                labelText: '经度',
                hintText: '−180 至 180',
                suffixText: '°',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '示例位置',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final preset in const [
                  ('上海', 31.2304, 121.4737),
                  ('北京', 39.9042, 116.4074),
                  ('深圳', 22.5431, 114.0579),
                ])
                  ActionChip(
                    label: Text(preset.$1),
                    avatar: const Icon(Icons.place_outlined, size: 16),
                    onPressed: enabled
                        ? () => onPresetSelected(preset.$2, preset.$3)
                        : null,
                    backgroundColor: AppColors.background,
                    side: const BorderSide(color: AppColors.border),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
