import 'dart:async';

import 'package:flutter/services.dart';

import 'src/generated/location_api.g.dart' as wire;
import 'src/runtime_models.dart';

export 'src/runtime_models.dart';

/// A single facade per engine. Native resources outlive UI routes.
final class LocationBridge {
  LocationBridge({BinaryMessenger? binaryMessenger})
    : _api = wire.NativeLocationApi(binaryMessenger: binaryMessenger),
      _messenger = binaryMessenger {
    wire.NativeLocationEvents.setUp(_Events(this), binaryMessenger: _messenger);
  }

  final wire.NativeLocationApi _api;
  final BinaryMessenger? _messenger;
  final _snapshots = StreamController<NativeSnapshot>.broadcast(sync: true);
  final _pairing = StreamController<NativePairingInteraction>.broadcast(
    sync: true,
  );
  bool _disposed = false;

  Stream<NativeSnapshot> get snapshots => _snapshots.stream;
  Stream<NativePairingInteraction> get pairingInteractions => _pairing.stream;

  Future<NativeSnapshot> attach() =>
      _call(() async => _snapshot(await _api.attach()));
  Future<NativeSnapshot> getSnapshot() =>
      _call(() async => _snapshot(await _api.getSnapshot()));
  Future<NativeCapabilities> getCapabilities() =>
      _call(() async => _capabilities(await _api.getCapabilities()));
  Future<NativeSnapshot> connect(String operationId) =>
      _call(() async => _snapshot(await _api.connect(operationId)));
  Future<NativeSnapshot> setLocation(
    String operationId,
    NativeCoordinate coordinate, {
    double accuracy = 5,
  }) => _call(
    () async => _snapshot(
      await _api.setLocation(
        wire.WireLocationRequest(
          operationId: operationId,
          coordinate: wire.WireCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
          ),
          accuracy: accuracy,
        ),
      ),
    ),
  );
  Future<NativeSnapshot> clearLocation(String operationId) =>
      _call(() async => _snapshot(await _api.clearLocation(operationId)));
  Future<NativeSnapshot> closeSession(String operationId) =>
      _call(() async => _snapshot(await _api.closeSession(operationId)));
  Future<NativeSnapshot> startPairing(String operationId) =>
      _call(() async => _snapshot(await _api.startPairing(operationId)));
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  }) => _call(
    () => _api.respondToPairing(
      wire.WirePairingResponse(
        interactionId: id,
        cancelled: cancelled,
        code: code,
      ),
    ),
  );
  Future<void> cancelPairing() => _call(_api.cancelPairing);
  Future<void> openSetup(SetupTarget target) => _call(
    () => _api.openSetup(wire.WireSetupTarget.values.byName(target.name)),
  );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _api.detach();
    } on PlatformException {
      // A missing engine must not prevent subscription disposal.
    } on MissingPluginException {
      // Unsupported environments have no native registration.
    } finally {
      wire.NativeLocationEvents.setUp(null, binaryMessenger: _messenger);
      await _snapshots.close();
      await _pairing.close();
    }
  }

  Future<T> _call<T>(Future<T> Function() action) async {
    if (_disposed) throw const NativeBridgeException('disposed', '定位桥接已关闭');
    try {
      return await action();
    } on PlatformException catch (error) {
      throw NativeBridgeException(error.code, error.message ?? '原生定位操作失败');
    } on MissingPluginException {
      throw const NativeBridgeException(
        'unsupportedPlatform',
        '此环境没有原生定位桥接，请在 Android 或 iPhone 上运行',
      );
    }
  }
}

final class _Events extends wire.NativeLocationEvents {
  _Events(this.owner);
  final LocationBridge owner;

  @override
  void onSnapshot(wire.WireSnapshot snapshot) {
    if (!owner._disposed) owner._snapshots.add(_snapshot(snapshot));
  }

  @override
  void onPairingInteraction(wire.WirePairingInteraction interaction) {
    if (owner._disposed) return;
    owner._pairing.add(
      NativePairingInteraction(
        id: interaction.id,
        operationId: interaction.operationId,
        kind: PairingKind.values.byName(interaction.kind.name),
        title: interaction.title,
        expiresAtMillis: interaction.expiresAtMillis,
        displayCode: interaction.displayCode,
      ),
    );
  }
}

NativeCoordinate _coordinate(wire.WireCoordinate value) =>
    NativeCoordinate(value.latitude, value.longitude);
NativeFailure? _failure(wire.WireFailure? value) => value == null
    ? null
    : NativeFailure(
        code: value.code,
        message: value.message,
        stage: value.stage,
        retryable: value.retryable,
        operationId: value.operationId,
      );
NativeCapabilities _capabilities(wire.WireCapabilities value) =>
    NativeCapabilities(
      platform: RuntimePlatform.values.byName(value.platform.name),
      osVersion: value.osVersion,
      engineAvailable: value.engineAvailable,
      supportsPairing: value.supportsPairing,
      isPaired: value.isPaired,
      prerequisites: value.prerequisites
          .map(
            (p) => NativePrerequisite(
              id: p.id,
              title: p.title,
              detail: p.detail,
              state: CheckState.values.byName(p.state.name),
              requiredForConnect: p.requiredForConnect,
              action: p.action == null
                  ? null
                  : SetupTarget.values.byName(p.action!.name),
            ),
          )
          .toList(),
    );
NativeSnapshot _snapshot(wire.WireSnapshot value) => NativeSnapshot(
  runtimeId: value.runtimeId,
  generation: value.generation,
  sequence: value.sequence,
  connection: ConnectionPhase.values.byName(value.connection.name),
  recoveryRequired: value.recoveryRequired,
  capabilities: _capabilities(value.capabilities),
  sessionId: value.sessionId,
  failure: _failure(value.failure),
  operation: value.operation == null
      ? null
      : NativeOperation(
          id: value.operation!.id,
          kind: OperationKind.values.byName(value.operation!.kind.name),
          state: CommandPhase.values.byName(value.operation!.state.name),
          occurredAtMillis: value.operation!.occurredAtMillis,
          coordinate: value.operation!.coordinate == null
              ? null
              : _coordinate(value.operation!.coordinate!),
          failure: _failure(value.operation!.failure),
        ),
  sample: value.sample == null
      ? null
      : NativeSample(
          coordinate: _coordinate(value.sample!.coordinate),
          accuracy: value.sample!.accuracy,
          timestampMillis: value.sample!.timestampMillis,
          isSimulated: value.sample!.isSimulated,
        ),
);
