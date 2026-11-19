import 'package:get/get.dart';

import '../../../services/location_session_service.dart';
import '../controllers/location_workspace_controller.dart';

class LocationWorkspaceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LocationWorkspaceController>(
      () => LocationWorkspaceController(Get.find<LocationSessionService>()),
    );
  }
}
