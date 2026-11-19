import 'package:get/get.dart';

import '../../../services/location_session_service.dart';
import '../controllers/device_setup_controller.dart';

class DeviceSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeviceSetupController>(
      () => DeviceSetupController(Get.find<LocationSessionService>()),
    );
  }
}
