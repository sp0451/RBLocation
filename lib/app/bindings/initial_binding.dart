import 'package:get/get.dart';
import 'package:location_bridge/location_bridge.dart';

import '../data/providers/native_location_provider.dart';
import '../data/repositories/location_session_repository.dart';
import '../data/repositories/native_location_session_repository.dart';
import '../services/location_session_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    final repository = NativeLocationSessionRepository(
      NativeLocationProvider(LocationBridge()),
    );
    Get.put<LocationSessionRepository>(repository, permanent: true);
    Get.put(LocationSessionService(repository), permanent: true);
  }
}
