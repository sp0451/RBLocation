import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/section_card.dart';

enum PairingInteractionMode { displayCode, enterCode, confirmOnDevice }

/// Pairing input lives only in this widget and is cleared when it leaves view.
class PairingInteractionPane extends StatefulWidget {
  const PairingInteractionPane({
    required this.title,
    required this.mode,
    required this.onSubmitted,
    required this.onCancelled,
    this.displayCode,
    this.expirationLabel,
    this.isExpired = false,
    super.key,
  });

  final String title;
  final PairingInteractionMode mode;
  final String? displayCode;
  final String? expirationLabel;
  final bool isExpired;
  final Future<void> Function(String?) onSubmitted;
  final Future<void> Function() onCancelled;

  @override
  State<PairingInteractionPane> createState() => _PairingInteractionPaneState();
}

class _PairingInteractionPaneState extends State<PairingInteractionPane> {
  final _code = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || widget.isExpired) return;
    String? submittedCode;
    if (widget.mode == PairingInteractionMode.enterCode) {
      if (_formKey.currentState?.validate() != true) return;
      submittedCode = _code.text.trim();
      _code.clear();
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmitted(submittedCode);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: widget.title,
      subtitle: widget.expirationLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.mode == PairingInteractionMode.enterCode)
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _code,
                enabled: !_submitting && !widget.isExpired,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '六位配对码',
                  helperText: '输入设备显示的临时配对码。',
                ),
                validator: (value) =>
                    RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : '请输入六位数字配对码',
              ),
            )
          else if (widget.mode == PairingInteractionMode.displayCode)
            Column(
              children: [
                const Text('请在系统配对界面输入以下临时配对码：'),
                const SizedBox(height: 16),
                Text(
                  widget.displayCode ?? '等待配对码',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            const Text('请在设备的系统提示中确认配对，完成后继续。'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting || widget.isExpired ? null : _submit,
            child: Text(
              widget.mode == PairingInteractionMode.enterCode
                  ? '提交配对码'
                  : '已完成，继续',
            ),
          ),
          TextButton(onPressed: widget.onCancelled, child: const Text('取消配对')),
        ],
      ),
    );
  }
}
