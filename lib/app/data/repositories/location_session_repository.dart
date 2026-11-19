import '../models/geo/wgs84_coordinate.dart';
import '../models/session/session_snapshot.dart';

abstract interface class LocationSessionRepository {
  Stream<SessionSnapshot> get snapshots;
  Stream<PairingPrompt> get pairingPrompts;
  Future<SessionSnapshot> initialize();
  Future<SessionSnapshot> refresh();
  Future<void> connect(String operationId);
  Future<void> setLocation(String operationId, Wgs84Coordinate coordinate);
  Future<void> clearLocation(String operationId);
  Future<void> startPairing(String operationId);
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  });
  Future<void> cancelPairing();
  Future<void> openSetup(SetupTarget target);
  Future<void> shutdown(String operationId);
  Future<void> dispose();
}
