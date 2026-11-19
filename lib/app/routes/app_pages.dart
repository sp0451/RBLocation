import 'package:get/get.dart';

import '../modules/device_setup/bindings/device_setup_binding.dart';
import '../modules/device_setup/views/device_setup_view.dart';
import '../modules/location_workspace/bindings/location_workspace_binding.dart';
import '../modules/location_workspace/views/location_workspace_view.dart';
import '../modules/startup/bindings/startup_binding.dart';
import '../modules/startup/views/startup_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.STARTUP;

  static final routes = [
    GetPage(
      name: _Paths.STARTUP,
      page: () => const StartupView(),
      binding: StartupBinding(),
    ),
    GetPage(
      name: _Paths.LOCATION_WORKSPACE,
      page: () => const LocationWorkspaceView(),
      binding: LocationWorkspaceBinding(),
    ),
    GetPage(
      name: _Paths.DEVICE_SETUP,
      page: () => const DeviceSetupView(),
      binding: DeviceSetupBinding(),
    ),
  ];
}
