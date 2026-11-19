import '../../../core/error/app_failure.dart';
import '../geo/wgs84_coordinate.dart';

enum RuntimePlatform { android, ios, unsupported }

enum SessionConnection { disconnected, connecting, ready, lost, closing }

enum OperationState {
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

enum PrerequisiteStatus { satisfied, missing, unknown }

enum SetupTarget {
  developerSettings,
  appSettings,
  locationSettings,
  locationPermission,
  notificationPermission,
  externalTunnel,
}

final class SessionPrerequisite {
  const SessionPrerequisite({
    required this.id,
    required this.title,
    required this.detail,
    required this.status,
    required this.requiredForConnect,
    this.action,
  });
  final String id;
  final String title;
  final String detail;
  final PrerequisiteStatus status;
  final bool requiredForConnect;
  final SetupTarget? action;
}

final class SessionCapabilities {
  SessionCapabilities({
    required this.platform,
    required this.osVersion,
    required this.engineAvailable,
    required this.supportsPairing,
    required this.isPaired,
    required List<SessionPrerequisite> prerequisites,
  }) : prerequisites = List.unmodifiable(prerequisites);
  factory SessionCapabilities.unknown() => SessionCapabilities(
    platform: RuntimePlatform.unsupported,
    osVersion: '',
    engineAvailable: false,
    supportsPairing: false,
    isPaired: false,
    prerequisites: const [],
  );
  final RuntimePlatform platform;
  final String osVersion;
  final bool engineAvailable;
  final bool supportsPairing;
  final bool isPaired;
  final List<SessionPrerequisite> prerequisites;
}

final class SessionOperation {
  const SessionOperation({
    required this.id,
    required this.kind,
    required this.state,
    required this.occurredAt,
    this.coordinate,
    this.failure,
  });
  final String id;
  final OperationKind kind;
  final OperationState state;
  final DateTime occurredAt;
  final Wgs84Coordinate? coordinate;
  final AppFailure? failure;
}

final class LocationSample {
  const LocationSample({
    required this.coordinate,
    required this.accuracy,
    required this.timestamp,
    this.isSimulated,
  });
  final Wgs84Coordinate coordinate;
  final double accuracy;
  final DateTime timestamp;
  final bool? isSimulated;
  bool isFresh(DateTime now) {
    final age = now.difference(timestamp);
    return !age.isNegative && age <= const Duration(seconds: 30);
  }
}

final class SessionSnapshot {
  const SessionSnapshot({
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
  factory SessionSnapshot.initial() => SessionSnapshot(
    runtimeId: 'unattached',
    generation: 0,
    sequence: -1,
    connection: SessionConnection.disconnected,
    recoveryRequired: false,
    capabilities: SessionCapabilities.unknown(),
  );
  final String runtimeId;
  final int generation;
  final int sequence;
  final SessionConnection connection;
  final bool recoveryRequired;
  final SessionCapabilities capabilities;
  final String? sessionId;
  final SessionOperation? operation;
  final LocationSample? sample;
  final AppFailure? failure;
}

enum PairingPromptKind { displayCode, enterCode, confirmOnDevice }

/// Ephemeral UI interaction, excluded from session snapshots and persistence.
final class PairingPrompt {
  const PairingPrompt({
    required this.id,
    required this.operationId,
    required this.kind,
    required this.title,
    required this.expiresAt,
    this.displayCode,
  });
  final String id;
  final String operationId;
  final PairingPromptKind kind;
  final String title;
  final DateTime expiresAt;
  final String? displayCode;
}
