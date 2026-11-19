import 'package:flutter/material.dart';

class LocationActionBar extends StatelessWidget {
  const LocationActionBar({
    required this.canConnect,
    required this.canSet,
    required this.canClear,
    required this.isBusy,
    required this.onConnectRequested,
    required this.onSetRequested,
    required this.onClearRequested,
    super.key,
  });

  final bool canConnect;
  final bool canSet;
  final bool canClear;
  final bool isBusy;
  final VoidCallback onConnectRequested;
  final VoidCallback onSetRequested;
  final VoidCallback onClearRequested;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: canSet ? onSetRequested : null,
          icon: isBusy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.location_on_outlined, size: 20),
          label: const Text('设置位置'),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: canConnect ? onConnectRequested : null,
              icon: const Icon(Icons.link_rounded, size: 19),
              label: const Text('连接设备'),
            ),
            OutlinedButton.icon(
              onPressed: canClear ? onClearRequested : null,
              icon: const Icon(Icons.stop_circle_outlined, size: 19),
              label: const Text('停止模拟'),
            ),
          ],
        ),
      ],
    );
  }
}
