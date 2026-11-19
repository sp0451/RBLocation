import 'dart:async';

import 'package:location_bridge/location_bridge.dart' as native;

import '../models/geo/wgs84_coordinate.dart';
import '../models/session/session_snapshot.dart';
import '../providers/native_location_provider.dart';
import 'location_session_repository.dart';
import 'native_session_mapper.dart';

/// Subscribes before attaching. Native snapshots are complete and ordered per runtime.
final class NativeLocationSessionRepository
    implements LocationSessionRepository {
  NativeLocationSessionRepository(this._source);
  final NativeLocationSource _source;
  final _snapshots = StreamController<SessionSnapshot>.broadcast(sync: true);
  final _pairing = StreamController<PairingPrompt>.broadcast(sync: true);
  final _buffer = <native.NativeSnapshot>[];
  final _retiredRuntimes = <String>{};
  StreamSubscription<native.NativeSnapshot>? _snapshotSubscription;
  StreamSubscription<native.NativePairingInteraction>? _pairingSubscription;
  SessionSnapshot? _latest;
  Future<SessionSnapshot>? _syncFuture;
  bool _syncing = false;
  bool _disposed = false;

  @override
  Stream<SessionSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PairingPrompt> get pairingPrompts => _pairing.stream;

  @override
  Future<SessionSnapshot> initialize() {
    _ensureOpen();
    _snapshotSubscription ??= _source.snapshots.listen(
      _receive,
      onError: _streamError,
    );
    _pairingSubscription ??= _source.pairingInteractions.listen((value) {
      if (!_disposed) _pairing.add(mapPairingPrompt(value));
    }, onError: _streamError);
    if (_latest != null) return Future.value(_latest!);
    return _synchronize(attach: true);
  }

  @override
  Future<SessionSnapshot> refresh() {
    _ensureOpen();
    return _latest == null ? initialize() : _synchronize();
  }

  Future<SessionSnapshot> _synchronize({bool attach = false}) {
    final existing = _syncFuture;
    if (existing != null) return existing;
    _syncing = true;
    final future = _readSnapshot(attach);
    _syncFuture = future;
    return future;
  }

  Future<SessionSnapshot> _readSnapshot(bool attach) async {
    var changedRuntimeDuringRead = false;
    try {
      final value = await (attach ? _source.attach() : _source.getSnapshot());
      _ensureOpen();
      _apply(value, authoritative: true);
      // Buffered events may be newer than the snapshot returned by attach.
      final buffered = List<native.NativeSnapshot>.of(_buffer);
      _buffer.clear();
      for (final event in buffered) {
        if (event.runtimeId == _latest?.runtimeId) {
          _apply(event);
        } else if (!_retiredRuntimes.contains(event.runtimeId)) {
          changedRuntimeDuringRead = true;
        }
      }
      return _latest!;
    } catch (error) {
      throw bridgeFailure(error, attach ? 'attach' : 'resync');
    } finally {
      _syncing = false;
      _syncFuture = null;
      if (changedRuntimeDuringRead && !_disposed) {
        // The engine may restart while a snapshot response is in flight. Ask
        // again after releasing this synchronization instead of dropping B's
        // only event while accepting A's older response.
        scheduleMicrotask(() {
          if (!_disposed) {
            unawaited(_synchronize().then<void>((_) {}, onError: _streamError));
          }
        });
      }
    }
  }

  void _receive(native.NativeSnapshot value) {
    if (_disposed || _retiredRuntimes.contains(value.runtimeId)) return;
    if (_syncing || _latest == null) {
      _bufferEvent(value);
      return;
    }
    final current = _latest!;
    if (value.runtimeId != current.runtimeId ||
        value.sequence > current.sequence + 1) {
      _bufferEvent(value);
      unawaited(_synchronize().then<void>((_) {}, onError: _streamError));
      return;
    }
    try {
      _apply(value);
    } catch (error) {
      _streamError(error);
    }
  }

  void _bufferEvent(native.NativeSnapshot value) {
    if (_buffer.length == 256) _buffer.removeAt(0);
    _buffer.add(value);
  }

  void _apply(native.NativeSnapshot value, {bool authoritative = false}) {
    if (_disposed || _retiredRuntimes.contains(value.runtimeId)) return;
    final current = _latest;
    if (current != null) {
      if (value.runtimeId != current.runtimeId) {
        if (!authoritative) return;
      } else if (value.generation < current.generation ||
          value.sequence < current.sequence ||
          (!authoritative && value.sequence == current.sequence)) {
        return;
      }
    }
    final mapped = mapNativeSnapshot(value);
    if (current != null && value.runtimeId != current.runtimeId) {
      _retiredRuntimes.add(current.runtimeId);
    }
    _latest = mapped;
    _snapshots.add(mapped);
  }

  void _streamError(Object error, [StackTrace? stack]) {
    if (!_disposed) _snapshots.addError(bridgeFailure(error, 'events'));
  }

  Future<void> _command(
    String id,
    Future<native.NativeSnapshot> Function() action,
  ) async {
    _ensureOpen();
    try {
      final result = await action();
      // A rejected call can return a response-only failure at the same watermark.
      // Do not replace an in-flight authoritative operation with that response.
      _receive(result);
      if (result.operation?.id == id &&
          result.operation?.state == native.CommandPhase.failed) {
        final failure = mapNativeFailure(
          result.operation?.failure ?? result.failure,
        );
        if (failure != null) throw failure;
      }
    } catch (error) {
      throw bridgeFailure(error, 'command');
    }
  }

  @override
  Future<void> connect(String operationId) =>
      _command(operationId, () => _source.connect(operationId));
  @override
  Future<void> setLocation(String operationId, Wgs84Coordinate coordinate) =>
      _command(
        operationId,
        () => _source.setLocation(
          operationId,
          native.NativeCoordinate(coordinate.latitude, coordinate.longitude),
        ),
      );
  @override
  Future<void> clearLocation(String operationId) =>
      _command(operationId, () => _source.clearLocation(operationId));
  @override
  Future<void> startPairing(String operationId) =>
      _command(operationId, () => _source.startPairing(operationId));
  @override
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  }) => _source.respondToPairing(id, code: code, cancelled: cancelled);
  @override
  Future<void> cancelPairing() => _source.cancelPairing();
  @override
  Future<void> openSetup(SetupTarget target) =>
      _source.openSetup(native.SetupTarget.values.byName(target.name));
  @override
  Future<void> shutdown(String operationId) =>
      _command(operationId, () => _source.closeSession(operationId));

  void _ensureOpen() {
    if (_disposed) {
      throw const native.NativeBridgeException('disposed', '会话数据源已关闭');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _snapshotSubscription?.cancel();
    await _pairingSubscription?.cancel();
    _buffer.clear();
    try {
      await _source.dispose();
    } finally {
      await _snapshots.close();
      await _pairing.close();
    }
  }
}
