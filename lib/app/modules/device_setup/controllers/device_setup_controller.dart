import 'package:get/get.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/models/session/session_snapshot.dart';
import '../../../services/location_session_service.dart';

class DeviceSetupController extends GetxController {
  DeviceSetupController(this._session);

  final LocationSessionService _session;

  SessionSnapshot get snapshot => _session.snapshot;
  bool get isBusy => _session.isBusy;
  PairingPrompt? get pairingPrompt => _session.pairingPrompt;
  DateTime get now => _session.now;
  AppFailure? get lastError => _session.lastError;

  Future<void> refreshPrerequisites() => _session.refreshPrerequisites();
  Future<void> openSetup(SetupTarget target) => _session.openSetup(target);
  Future<void> startPairing() => _session.startPairing();
  Future<void> submitPairing(String interactionId, String? code) =>
      _session.respondToPairing(interactionId, code: code);
  Future<void> cancelPairing() => _session.cancelPairing();
}
