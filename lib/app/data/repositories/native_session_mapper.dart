import 'package:location_bridge/location_bridge.dart' as native;

import '../../core/error/app_failure.dart';
import '../models/geo/wgs84_coordinate.dart';
import '../models/session/session_snapshot.dart';

AppFailure? mapNativeFailure(native.NativeFailure? value) => value == null
    ? null
    : AppFailure(
        code: value.code,
        message: value.message,
        stage: value.stage,
        retryable: value.retryable,
      );

Wgs84Coordinate _coordinate(native.NativeCoordinate value) =>
    Wgs84Coordinate(latitude: value.latitude, longitude: value.longitude);

SessionSnapshot mapNativeSnapshot(native.NativeSnapshot value) {
  final operation = value.operation;
  final sample = value.sample;
  return SessionSnapshot(
    runtimeId: value.runtimeId,
    generation: value.generation,
    sequence: value.sequence,
    connection: SessionConnection.values.byName(value.connection.name),
    recoveryRequired: value.recoveryRequired,
    sessionId: value.sessionId,
    failure: mapNativeFailure(value.failure),
    capabilities: SessionCapabilities(
      platform: RuntimePlatform.values.byName(value.capabilities.platform.name),
      osVersion: value.capabilities.osVersion,
      engineAvailable: value.capabilities.engineAvailable,
      supportsPairing: value.capabilities.supportsPairing,
      isPaired: value.capabilities.isPaired,
      prerequisites: value.capabilities.prerequisites
          .map(
            (p) => SessionPrerequisite(
              id: p.id,
              title: p.title,
              detail: p.detail,
              status: PrerequisiteStatus.values.byName(p.state.name),
              requiredForConnect: p.requiredForConnect,
              action: p.action == null
                  ? null
                  : SetupTarget.values.byName(p.action!.name),
            ),
          )
          .toList(),
    ),
    operation: operation == null
        ? null
        : SessionOperation(
            id: operation.id,
            kind: OperationKind.values.byName(operation.kind.name),
            state: OperationState.values.byName(operation.state.name),
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              operation.occurredAtMillis,
            ),
            coordinate: operation.coordinate == null
                ? null
                : _coordinate(operation.coordinate!),
            failure: mapNativeFailure(operation.failure),
          ),
    sample: sample == null || !sample.accuracy.isFinite || sample.accuracy < 0
        ? null
        : LocationSample(
            coordinate: _coordinate(sample.coordinate),
            accuracy: sample.accuracy,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              sample.timestampMillis,
            ),
            isSimulated: sample.isSimulated,
          ),
  );
}

PairingPrompt mapPairingPrompt(native.NativePairingInteraction value) =>
    PairingPrompt(
      id: value.id,
      operationId: value.operationId,
      kind: PairingPromptKind.values.byName(value.kind.name),
      title: value.title,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(value.expiresAtMillis),
      displayCode: value.displayCode,
    );

AppFailure bridgeFailure(Object error, String stage) => error is AppFailure
    ? error
    : error is native.NativeBridgeException
    ? AppFailure(
        code: error.code,
        message: error.message,
        stage: stage,
        retryable:
            error.code != 'unsupportedPlatform' && error.code != 'disposed',
      )
    : AppFailure(
        code: 'bridgeFailure',
        message: '无法读取或执行原生定位操作，请刷新设备状态后重试。',
        stage: stage,
        retryable: true,
      );
