enum RuntimePlatform { android, ios, unsupported }

enum ConnectionPhase { disconnected, connecting, ready, lost, closing }

enum CommandPhase {
  pending,
  sent,
  acknowledged,
  failed,
  cancelled,
  indeterminate,
}

enum OperationKind {
  connect,
  setLocation,
  clearLocation,
  closeSession,
  pairing,
}

enum CheckState { satisfied, missing, unknown }

enum SetupTarget {
  developerSettings,
  appSettings,
  locationSettings,
  locationPermission,
  notificationPermission,
  externalTunnel,
}

enum PairingKind { displayCode, enterCode, confirmOnDevice }

final class NativeCoordinate {
  const NativeCoordinate(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

final class NativeFailure {
  const NativeFailure({
    required this.code,
    required this.message,
    required this.stage,
    required this.retryable,
    this.operationId,
  });
  final String code;
  final String message;
  final String stage;
  final bool retryable;
  final String? operationId;
}

final class NativePrerequisite {
  const NativePrerequisite({
    required this.id,
    required this.title,
    required this.detail,
    required this.state,
    required this.requiredForConnect,
    this.action,
  });
  final String id;
  final String title;
  final String detail;
  final CheckState state;
  final bool requiredForConnect;
  final SetupTarget? action;
}

final class NativeCapabilities {
  NativeCapabilities({
    required this.platform,
    required this.osVersion,
    required this.engineAvailable,
    required this.supportsPairing,
    required this.isPaired,
    required List<NativePrerequisite> prerequisites,
  }) : prerequisites = List.unmodifiable(prerequisites);
  final RuntimePlatform platform;
  final String osVersion;
  final bool engineAvailable;
  final bool supportsPairing;
  final bool isPaired;
  final List<NativePrerequisite> prerequisites;
}

final class NativeOperation {
  const NativeOperation({
    required this.id,
    required this.kind,
    required this.state,
    required this.occurredAtMillis,
    this.coordinate,
    this.failure,
  });
  final String id;
  final OperationKind kind;
  final CommandPhase state;
  final int occurredAtMillis;
  final NativeCoordinate? coordinate;
  final NativeFailure? failure;
}

final class NativeSample {
  const NativeSample({
    required this.coordinate,
    required this.accuracy,
    required this.timestampMillis,
    this.isSimulated,
  });
  final NativeCoordinate coordinate;
  final double accuracy;
  final int timestampMillis;
  final bool? isSimulated;
}

final class NativeSnapshot {
  const NativeSnapshot({
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
  final String runtimeId;
  final int generation;
  final int sequence;
  final ConnectionPhase connection;
  final bool recoveryRequired;
  final NativeCapabilities capabilities;
  final String? sessionId;
  final NativeOperation? operation;
  final NativeSample? sample;
  final NativeFailure? failure;
}

/// Transient pairing data. Never put this object in snapshots or logs.
final class NativePairingInteraction {
  const NativePairingInteraction({
    required this.id,
    required this.operationId,
    required this.kind,
    required this.title,
    required this.expiresAtMillis,
    this.displayCode,
  });
  final String id;
  final String operationId;
  final PairingKind kind;
  final String title;
  final int expiresAtMillis;
  final String? displayCode;
}

final class NativeBridgeException implements Exception {
  const NativeBridgeException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}
