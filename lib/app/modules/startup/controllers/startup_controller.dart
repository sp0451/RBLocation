import 'package:get/get.dart';

import '../../../services/location_session_service.dart';

class StartupController extends GetxController {
  StartupController(this._session);

  final LocationSessionService _session;

  InitializationStatus get status => _session.initializationStatus;
  String get errorMessage =>
      _session.initializationError?.message ?? '初始化没有完成，请重试。';

  Future<void> initialize() => _session.initialize();
  Future<void> retry() => _session.retryInitialization();
}
