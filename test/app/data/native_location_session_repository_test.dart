import 'dart:async';

import 'package:clocation/app/core/error/app_failure.dart';
import 'package:clocation/app/data/models/geo/wgs84_coordinate.dart';
import 'package:clocation/app/data/models/session/session_snapshot.dart'
    as domain;
import 'package:clocation/app/data/providers/native_location_provider.dart';
import 'package:clocation/app/data/repositories/native_location_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_bridge/location_bridge.dart';

NativeSnapshot snapshot(
  int sequence, {
  String runtime = 'native-1',
  int generation = 0,
  NativeOperation? operation,
  bool paired = false,
}) => NativeSnapshot(
  runtimeId: runtime,
  generation: generation,
  sequence: sequence,
  connection: ConnectionPhase.ready,
  recoveryRequired: true,
  capabilities: NativeCapabilities(
    platform: RuntimePlatform.ios,
    osVersion: '27.0.1',
    engineAvailable: true,
    supportsPairing: true,
    isPaired: paired,
    prerequisites: [],
  ),
  operation: operation,
);

class FakeSource implements NativeLocationSource {
  final events = StreamController<NativeSnapshot>.broadcast(sync: true);
  final pairing = StreamController<NativePairingInteraction>.broadcast(
    sync: true,
  );
  final attachResult = Completer<NativeSnapshot>();
  NativeSnapshot nextSnapshot = snapshot(0);
  NativeSnapshot? commandResult;
  Future<NativeSnapshot>? snapshotResult;
  int refreshes = 0;
  bool disposed = false;
  @override
  Stream<NativeSnapshot> get snapshots => events.stream;
  @override
  Stream<NativePairingInteraction> get pairingInteractions => pairing.stream;
  @override
  Future<NativeSnapshot> attach() => attachResult.future;
  @override
  Future<NativeSnapshot> getSnapshot() async {
    refreshes++;
    final delayed = snapshotResult;
    snapshotResult = null;
    if (delayed != null) return delayed;
    return nextSnapshot;
  }

  @override
  Future<NativeSnapshot> connect(String id) async =>
      commandResult ?? nextSnapshot;
  @override
  Future<NativeSnapshot> setLocation(
    String id,
    NativeCoordinate coordinate,
  ) async => commandResult ?? nextSnapshot;
  @override
  Future<NativeSnapshot> clearLocation(String id) async =>
      commandResult ?? nextSnapshot;
  @override
  Future<NativeSnapshot> closeSession(String id) async => nextSnapshot;
  @override
  Future<NativeSnapshot> startPairing(String id) async => nextSnapshot;
  @override
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  }) async {}
  @override
  Future<void> cancelPairing() async {}
  @override
  Future<void> openSetup(SetupTarget target) async {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
    await pairing.close();
  }
}

void main() {
  late FakeSource source;
  late NativeLocationSessionRepository repository;
  late List<domain.SessionSnapshot> received;
  setUp(() {
    source = FakeSource();
    repository = NativeLocationSessionRepository(source);
    received = [];
    repository.snapshots.listen(received.add);
  });
  tearDown(() => repository.dispose());
  Future<void> attach() async {
    final future = repository.initialize();
    source.attachResult.complete(snapshot(0));
    await future;
  }

  test(
    'subscribes before attach and drains only snapshots newer than its watermark',
    () async {
      final future = repository.initialize();
      source.events.add(snapshot(0));
      source.events.add(snapshot(1));
      source.attachResult.complete(snapshot(0));
      expect((await future).sequence, 1);
      expect(received.map((s) => s.sequence), [0, 1]);
      source.events.add(snapshot(1));
      source.events.add(snapshot(0));
      expect(received.length, 2);
    },
  );

  test(
    'resynchronizes gaps and never applies old generation after stop',
    () async {
      await attach();
      source.nextSnapshot = snapshot(3, generation: 1);
      source.events.add(snapshot(3, generation: 1));
      await Future<void>.delayed(Duration.zero);
      expect(source.refreshes, 1);
      expect(received.last.generation, 1);
      source.events.add(snapshot(4, generation: 0));
      expect(received.last.sequence, 3);
    },
  );

  test(
    'new runtime requires snapshot handshake and retires old runtime',
    () async {
      await attach();
      source.nextSnapshot = snapshot(0, runtime: 'native-2');
      source.events.add(source.nextSnapshot);
      await Future<void>.delayed(Duration.zero);
      expect(received.last.runtimeId, 'native-2');
      source.events.add(snapshot(1));
      expect(received.last.runtimeId, 'native-2');
    },
  );

  test(
    'same-watermark rejection surfaces error without replacing authoritative operation',
    () async {
      await attach();
      source.commandResult = snapshot(
        0,
        operation: const NativeOperation(
          id: 'set-1',
          kind: OperationKind.setLocation,
          state: CommandPhase.failed,
          occurredAtMillis: 0,
          failure: NativeFailure(
            code: 'busy',
            message: '已有命令执行中',
            stage: 'set',
            retryable: true,
          ),
        ),
      );
      await expectLater(
        repository.setLocation(
          'set-1',
          Wgs84Coordinate(latitude: 0, longitude: 0),
        ),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'busy')),
      );
      expect(received.last.operation, isNull);
    },
  );

  test(
    'engine restarting during refresh triggers a second handshake',
    () async {
      await attach();
      final staleResponse = Completer<NativeSnapshot>();
      source.snapshotResult = staleResponse.future;
      final refreshing = repository.refresh();
      source.nextSnapshot = snapshot(0, runtime: 'native-2');
      source.events.add(source.nextSnapshot);
      staleResponse.complete(snapshot(0));
      await refreshing;
      await Future<void>.delayed(Duration.zero);
      expect(source.refreshes, 2);
      expect(received.last.runtimeId, 'native-2');
    },
  );

  test(
    'explicit refresh updates prerequisites even at the same sequence',
    () async {
      await attach();
      source.nextSnapshot = snapshot(0, paired: true);
      expect((await repository.refresh()).capabilities.isPaired, isTrue);
      expect(received.last.capabilities.isPaired, isTrue);
      await repository.dispose();
      expect(source.disposed, isTrue);
      expect(source.events.hasListener, isFalse);
    },
  );
}
