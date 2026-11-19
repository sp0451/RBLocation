import 'dart:async';

import 'package:clocation/app/core/error/app_failure.dart';
import 'package:clocation/app/data/models/geo/wgs84_coordinate.dart';
import 'package:clocation/app/data/models/session/session_snapshot.dart';
import 'package:clocation/app/data/repositories/location_session_repository.dart';
import 'package:clocation/app/services/location_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements LocationSessionRepository {
  final events = StreamController<SessionSnapshot>.broadcast(sync: true);
  final pairing = StreamController<PairingPrompt>.broadcast(sync: true);
  int initializes = 0;
  int shutdowns = 0;
  bool failInitialization = false;
  bool failShutdown = false;
  bool failRefresh = false;
  bool disposed = false;
  Completer<void>? setResult;
  Completer<void>? closeResult;
  int sets = 0;
  String? pairingOperation;
  SessionSnapshot current = SessionSnapshot(
    runtimeId: 'native',
    generation: 0,
    sequence: 0,
    connection: SessionConnection.ready,
    recoveryRequired: false,
    capabilities: SessionCapabilities(
      platform: RuntimePlatform.ios,
      osVersion: '27.0.1',
      engineAvailable: true,
      supportsPairing: true,
      isPaired: true,
      prerequisites: [],
    ),
  );
  @override
  Stream<SessionSnapshot> get snapshots => events.stream;
  @override
  Stream<PairingPrompt> get pairingPrompts => pairing.stream;
  @override
  Future<SessionSnapshot> initialize() async {
    initializes++;
    if (failInitialization) {
      throw const AppFailure(
        code: 'attach',
        message: '连接失败',
        stage: 'attach',
        retryable: true,
      );
    }
    return current;
  }

  @override
  Future<SessionSnapshot> refresh() async {
    if (failRefresh) {
      throw const AppFailure(
        code: 'transport',
        message: '连接失败',
        stage: 'transport',
        retryable: true,
      );
    }
    return current;
  }

  @override
  Future<void> connect(String operationId) async {}
  @override
  Future<void> setLocation(String operationId, Wgs84Coordinate coordinate) {
    sets++;
    return setResult?.future ?? Future.value();
  }

  @override
  Future<void> clearLocation(String operationId) async {
    current = SessionSnapshot(
      runtimeId: current.runtimeId,
      generation: 1,
      sequence: 1,
      connection: SessionConnection.ready,
      recoveryRequired: true,
      capabilities: current.capabilities,
      operation: SessionOperation(
        id: operationId,
        kind: OperationKind.clearLocation,
        state: OperationState.sent,
        occurredAt: DateTime.now(),
      ),
    );
    events.add(current);
  }

  @override
  Future<void> startPairing(String operationId) async {
    pairingOperation = operationId;
    current = SessionSnapshot(
      runtimeId: current.runtimeId,
      generation: 0,
      sequence: current.sequence + 1,
      connection: SessionConnection.disconnected,
      recoveryRequired: true,
      capabilities: current.capabilities,
      operation: SessionOperation(
        id: operationId,
        kind: OperationKind.pairing,
        state: OperationState.pending,
        occurredAt: DateTime.now(),
      ),
    );
    events.add(current);
  }

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
  Future<void> shutdown(String operationId) async {
    shutdowns++;
    await closeResult?.future;
    if (failShutdown) {
      throw const AppFailure(
        code: 'clearFailed',
        message: '清除未确认',
        stage: 'shutdown',
        retryable: true,
      );
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
    await pairing.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRepository repository;
  late LocationSessionService service;
  setUp(() {
    repository = FakeRepository();
    service = LocationSessionService(repository);
  });
  tearDown(() async {
    try {
      await service.shutdown();
    } on AppFailure {
      /* asserted by shutdown test */
    }
  });

  test(
    'initialization shares a future, retries errors, and subscribes only once',
    () async {
      repository.failInitialization = true;
      final first = service.initialize();
      expect(identical(first, service.initialize()), isTrue);
      await first;
      expect(service.initializationStatus, InitializationStatus.failed);
      expect(service.initializationError?.code, 'attach');
      repository.failInitialization = false;
      await service.retryInitialization();
      expect(service.initializationStatus, InitializationStatus.ready);
      expect(repository.initializes, 2);
      await service.initialize();
      expect(repository.initializes, 2);
    },
  );

  test(
    'stop remains enabled during pending set and late set failure cannot replace stop',
    () async {
      await service.initialize();
      repository.setResult = Completer<void>();
      final setting = service.setLocation(
        Wgs84Coordinate(latitude: 31, longitude: 121),
      );
      expect(service.isBusy, isTrue);
      expect(service.canSet, isFalse);
      expect(service.canClear, isTrue);
      await service.clearSimulation();
      repository.setResult!.completeError(
        const AppFailure(
          code: 'oldSet',
          message: '旧设置失效',
          stage: 'set',
          retryable: true,
        ),
      );
      await setting;
      expect(service.lastError, isNull);
      expect(service.snapshot.operation?.kind, OperationKind.clearLocation);
      expect(service.snapshot.recoveryRequired, isTrue);
      expect(service.canSet, isTrue);
    },
  );

  test('command errors are visible without fabricating native state', () async {
    await service.initialize();
    repository.setResult = Completer<void>();
    final setting = service.setLocation(
      Wgs84Coordinate(latitude: 0, longitude: 0),
    );
    repository.setResult!.completeError(
      const AppFailure(
        code: 'transport',
        message: '隧道断开',
        stage: 'set',
        retryable: true,
      ),
    );
    await setting;
    expect(service.lastError?.code, 'transport');
    expect(service.snapshot.operation, isNull);
    expect(service.snapshot.sample, isNull);
  });

  test(
    'shutdown is awaited and idempotent, removes listeners even if clearing fails',
    () async {
      await service.initialize();
      repository.failShutdown = true;
      await expectLater(service.shutdown(), throwsA(isA<AppFailure>()));
      expect(repository.disposed, isTrue);
      expect(repository.events.hasListener, isFalse);
      expect(service.canSet, isFalse);
      await expectLater(service.shutdown(), throwsA(isA<AppFailure>()));
      expect(repository.shutdowns, 1);
      expect(service.lastError?.code, 'clearFailed');
    },
  );

  test('shutdown blocks new commands before native close completes', () async {
    await service.initialize();
    repository.closeResult = Completer<void>();
    final closing = service.shutdown();
    expect(service.canSet, isFalse);
    expect(service.canClear, isFalse);
    await service.setLocation(Wgs84Coordinate(latitude: 0, longitude: 0));
    expect(repository.sets, 0);
    repository.closeResult!.complete();
    await closing;
  });

  PairingPrompt prompt(String operationId) => PairingPrompt(
    id: 'interaction-$operationId',
    operationId: operationId,
    kind: PairingPromptKind.displayCode,
    title: '配对',
    expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    displayCode: '123456',
  );

  test(
    'saved pairing credentials do not dismiss an active re-pairing code',
    () async {
      await service.initialize();
      await service.startPairing();
      repository.pairing.add(prompt(repository.pairingOperation!));
      repository.events.add(repository.current);
      expect(service.pairingPrompt?.operationId, repository.pairingOperation);
    },
  );

  test(
    'cancelled, terminated or foreign attempts cannot revive a pairing prompt',
    () async {
      await service.initialize();
      await service.startPairing();
      final active = prompt(repository.pairingOperation!);
      repository.pairing.add(prompt('older-attempt'));
      expect(service.pairingPrompt, isNull);
      repository.pairing.add(active);
      expect(service.pairingPrompt, isNotNull);
      await service.cancelPairing();
      repository.pairing.add(active);
      expect(service.pairingPrompt, isNull);
    },
  );

  test('observation freshness never derives from command target', () {
    final now = DateTime(2026, 10, 20, 10);
    final sample = LocationSample(
      coordinate: Wgs84Coordinate(latitude: 0, longitude: 0),
      accuracy: 10,
      timestamp: now.subtract(const Duration(seconds: 31)),
      isSimulated: false,
    );
    expect(sample.isFresh(now), isFalse);
    expect(sample.isFresh(now.subtract(const Duration(seconds: 60))), isFalse);
  });

  test('successful auxiliary retry clears its own transport error', () async {
    await service.initialize();
    repository.failRefresh = true;
    await service.refreshPrerequisites();
    expect(service.lastError?.code, 'transport');
    repository.failRefresh = false;
    await service.refreshPrerequisites();
    expect(service.lastError, isNull);
  });
}
