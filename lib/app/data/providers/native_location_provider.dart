import 'package:location_bridge/location_bridge.dart';

abstract interface class NativeLocationSource {
  Stream<NativeSnapshot> get snapshots;
  Stream<NativePairingInteraction> get pairingInteractions;
  Future<NativeSnapshot> attach();
  Future<NativeSnapshot> getSnapshot();
  Future<NativeSnapshot> connect(String id);
  Future<NativeSnapshot> setLocation(String id, NativeCoordinate coordinate);
  Future<NativeSnapshot> clearLocation(String id);
  Future<NativeSnapshot> closeSession(String id);
  Future<NativeSnapshot> startPairing(String id);
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  });
  Future<void> cancelPairing();
  Future<void> openSetup(SetupTarget target);
  Future<void> dispose();
}

/// All native plugin access is confined to this data source.
class NativeLocationProvider implements NativeLocationSource {
  NativeLocationProvider(this._bridge);
  final LocationBridge _bridge;
  @override
  Stream<NativeSnapshot> get snapshots => _bridge.snapshots;
  @override
  Stream<NativePairingInteraction> get pairingInteractions =>
      _bridge.pairingInteractions;
  @override
  Future<NativeSnapshot> attach() => _bridge.attach();
  @override
  Future<NativeSnapshot> getSnapshot() => _bridge.getSnapshot();
  @override
  Future<NativeSnapshot> connect(String id) => _bridge.connect(id);
  @override
  Future<NativeSnapshot> setLocation(String id, NativeCoordinate coordinate) =>
      _bridge.setLocation(id, coordinate);
  @override
  Future<NativeSnapshot> clearLocation(String id) => _bridge.clearLocation(id);
  @override
  Future<NativeSnapshot> closeSession(String id) => _bridge.closeSession(id);
  @override
  Future<NativeSnapshot> startPairing(String id) => _bridge.startPairing(id);
  @override
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  }) => _bridge.respondToPairing(id, code: code, cancelled: cancelled);
  @override
  Future<void> cancelPairing() => _bridge.cancelPairing();
  @override
  Future<void> openSetup(SetupTarget target) => _bridge.openSetup(target);
  @override
  Future<void> dispose() => _bridge.dispose();
}
