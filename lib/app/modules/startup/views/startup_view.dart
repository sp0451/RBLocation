import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../routes/app_pages.dart';
import '../../../services/location_session_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/inline_notice.dart';
import '../controllers/startup_controller.dart';

class StartupView extends GetView<StartupController> {
  const StartupView({super.key});

  @override
  Widget build(BuildContext context) => _StartupContent(controller: controller);
}

class _StartupContent extends StatefulWidget {
  const _StartupContent({required this.controller});

  final StartupController controller;

  @override
  State<_StartupContent> createState() => _StartupContentState();
}

class _StartupContentState extends State<_StartupContent> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize({bool retry = false}) async {
    if (retry) {
      await widget.controller.retry();
    } else {
      await widget.controller.initialize();
    }
    if (mounted && widget.controller.status == InitializationStatus.ready) {
      Get.offNamed<void>(Routes.LOCATION_WORKSPACE);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'CLocation',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '让测试位置，有据可查。',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 36),
                  Obx(() {
                    final status = widget.controller.status;
                    if (status == InitializationStatus.failed) {
                      return Column(
                        children: [
                          InlineNotice(
                            title: '初始化失败',
                            message: widget.controller.errorMessage,
                            tone: NoticeTone.error,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _initialize(retry: true),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重新初始化'),
                          ),
                        ],
                      );
                    }
                    return const Column(
                      children: [
                        SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '正在读取设备能力与会话状态…',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
