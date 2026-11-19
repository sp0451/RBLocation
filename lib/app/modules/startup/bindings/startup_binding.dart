import 'package:get/get.dart';

import '../../../services/location_session_service.dart';
import '../controllers/startup_controller.dart';

class StartupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StartupController>(
      () => StartupController(Get.find<LocationSessionService>()),
    );
  }
}
