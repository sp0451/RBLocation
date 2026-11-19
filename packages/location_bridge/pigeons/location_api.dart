import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/location_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/clocation/location_bridge/generated/LocationApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.clocation.location_bridge.generated',
    ),
    swiftOut:
        'ios/location_bridge/Sources/location_bridge/Generated/LocationApi.g.swift',
    dartPackageName: 'location_bridge',
  ),
)
enum WirePlatform { android, ios, unsupported }

enum WireConnection { disconnected, connecting, ready, lost, closing }

enum WireCommandState {
  pending,
  sent,
  acknowledged,
  failed,
  cancelled,
  indeterminate,
}

enum WireOperationKind {
  connect,
  setLocation,
  clearLocation,
  closeSession,
  pairing,
}

enum WireCheckState { satisfied, missing, unknown }

enum WireSetupTarget {
  developerSettings,
  appSettings,
  locationSettings,
  locationPermission,
  notificationPermission,
  externalTunnel,
}

enum WirePairingKind { displayCode, enterCode, confirmOnDevice }

class WireCoordinate {
  WireCoordinate({required this.latitude, required this.longitude});
  double latitude;
  double longitude;
}

class WireFailure {
  WireFailure({
    required this.code,
    required this.message,
    required this.stage,
    required this.retryable,
    this.operationId,
  });
  String code;
  String message;
  String stage;
  bool retryable;
  String? operationId;
}

class WirePrerequisite {
  WirePrerequisite({
    required this.id,
    required this.title,
    required this.detail,
    required this.state,
    required this.requiredForConnect,
    this.action,
  });
  String id;
  String title;
  String detail;
  WireCheckState state;
  bool requiredForConnect;
  WireSetupTarget? action;
}

class WireCapabilities {
  WireCapabilities({
    required this.platform,
    required this.osVersion,
    required this.engineAvailable,
    required this.supportsPairing,
    required this.isPaired,
    required this.prerequisites,
  });
  WirePlatform platform;
  String osVersion;
  bool engineAvailable;
  bool supportsPairing;
  bool isPaired;
  List<WirePrerequisite> prerequisites;
}

class WireOperation {
  WireOperation({
    required this.id,
    required this.kind,
    required this.state,
    required this.occurredAtMillis,
    this.coordinate,
    this.failure,
  });
  String id;
  WireOperationKind kind;
  WireCommandState state;
  int occurredAtMillis;
  WireCoordinate? coordinate;
  WireFailure? failure;
}

class WireSample {
  WireSample({
    required this.coordinate,
    required this.accuracy,
    required this.timestampMillis,
    this.isSimulated,
  });
  WireCoordinate coordinate;
  double accuracy;
  int timestampMillis;
  bool? isSimulated;
}

class WireSnapshot {
  WireSnapshot({
    required this.runtimeId,
    required this.generation,
    required this.sequence,
    required this.connection,
    required this.recoveryRequired,
    required this.capabilities,
    this.sessionId,
    this.operation,
    this.sample,
    this.failure,
  });
  String runtimeId;
  int generation;
  int sequence;
  WireConnection connection;
  bool recoveryRequired;
  WireCapabilities capabilities;
  String? sessionId;
  WireOperation? operation;
  WireSample? sample;
  WireFailure? failure;
}

class WireLocationRequest {
  WireLocationRequest({
    required this.operationId,
    required this.coordinate,
    required this.accuracy,
  });
  String operationId;
  WireCoordinate coordinate;
  double accuracy;
}

class WirePairingInteraction {
  WirePairingInteraction({
    required this.id,
    required this.operationId,
    required this.kind,
    required this.title,
    required this.expiresAtMillis,
    this.displayCode,
  });
  String id;
  String operationId;
  WirePairingKind kind;
  String title;
  int expiresAtMillis;
  String? displayCode;
}

class WirePairingResponse {
  WirePairingResponse({
    required this.interactionId,
    required this.cancelled,
    this.code,
  });
  String interactionId;
  bool cancelled;
  String? code;
}

@HostApi()
abstract class NativeLocationApi {
  @async
  WireSnapshot attach();
  @async
  WireCapabilities getCapabilities();
  @async
  WireSnapshot getSnapshot();
  @async
  WireSnapshot connect(String operationId);
  @async
  WireSnapshot setLocation(WireLocationRequest request);
  @async
  WireSnapshot clearLocation(String operationId);
  @async
  WireSnapshot closeSession(String operationId);
  @async
  WireSnapshot startPairing(String operationId);
  @async
  void respondToPairing(WirePairingResponse response);
  @async
  void cancelPairing();
  @async
  void openSetup(WireSetupTarget target);
  @async
  void detach();
}

@FlutterApi()
abstract class NativeLocationEvents {
  void onSnapshot(WireSnapshot snapshot);
  void onPairingInteraction(WirePairingInteraction interaction);
}
