import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../core/error/app_failure.dart';
import '../data/models/geo/wgs84_coordinate.dart';
import '../data/models/session/session_snapshot.dart';
import '../data/repositories/location_session_repository.dart';
import '../data/repositories/native_session_mapper.dart';

enum InitializationStatus { loading, ready, failed }

/// Application-scoped orchestration. Native owns the actual device session.
class LocationSessionService extends GetxService with WidgetsBindingObserver {
  LocationSessionService(this._repository);
  final LocationSessionRepository _repository;
  final _snapshot = SessionSnapshot.initial().obs;
  final _initialization = InitializationStatus.loading.obs;
  final _initializationError = Rxn<AppFailure>();
  final _actionError = Rxn<AppFailure>();
  final _pairingPrompt = Rxn<PairingPrompt>();
  final _now = DateTime.now().obs;
  final _pendingCount = 0.obs;
  final _clearing = false.obs;
  final _closing = false.obs;
  StreamSubscription<SessionSnapshot>? _snapshotSubscription;
  StreamSubscription<PairingPrompt>? _pairingSubscription;
  Timer? _clock;
  Future<void>? _initializing;
  Future<void>? _shutdownFuture;
  bool _closed = false;
  int _intent = 0;
  int _nextOperation = 0;
  String? _pairingAttemptId;
  String? _auxiliaryErrorStage;

  InitializationStatus get initializationStatus => _initialization.value;
  AppFailure? get initializationError => _initializationError.value;
  AppFailure? get lastError => _actionError.value ?? snapshot.failure;
  SessionSnapshot get snapshot => _snapshot.value;
  PairingPrompt? get pairingPrompt => _pairingPrompt.value;
  DateTime get now => _now.value;
  bool get _nativePending =>
      snapshot.operation?.state == OperationState.pending;
  bool get isBusy => _pendingCount.value > 0 || _nativePending;
  bool get _ready =>
      !_closed &&
      !_closing.value &&
      initializationStatus == InitializationStatus.ready;
  bool get canConnect =>
      _ready &&
      snapshot.capabilities.engineAvailable &&
      !isBusy &&
      (snapshot.connection == SessionConnection.disconnected ||
          snapshot.connection == SessionConnection.lost) &&
      !snapshot.capabilities.prerequisites.any(
        (p) => p.requiredForConnect && p.status == PrerequisiteStatus.missing,
      );
  bool get canSet =>
      _ready &&
      snapshot.capabilities.engineAvailable &&
      snapshot.connection == SessionConnection.ready &&
      !isBusy;
  // Stop remains reachable while an earlier set is still pending.
  bool get canClear =>
      _ready &&
      snapshot.capabilities.engineAvailable &&
      !_clearing.value &&
      (snapshot.recoveryRequired ||
          snapshot.connection == SessionConnection.ready ||
          snapshot.operation?.kind == OperationKind.setLocation);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
  }

  Future<void> initialize() {
    if (_closed || initializationStatus == InitializationStatus.ready) {
      return Future.value();
    }
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    _initialization.value = InitializationStatus.loading;
    _initializationError.value = null;
    _snapshotSubscription ??= _repository.snapshots.listen(
      _acceptSnapshot,
      onError: (Object error) {
        if (!_closed) {
          _auxiliaryErrorStage = null;
          _actionError.value = bridgeFailure(error, 'events');
        }
      },
    );
    _pairingSubscription ??= _repository.pairingPrompts.listen((prompt) {
      if (!_closed &&
          !_closing.value &&
          _pairingAttemptId != null &&
          prompt.operationId == _pairingAttemptId &&
          prompt.expiresAt.isAfter(DateTime.now())) {
        _pairingPrompt.value = prompt;
      }
    });
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_closed) return;
      _now.value = DateTime.now();
      final prompt = _pairingPrompt.value;
      if (prompt != null && !prompt.expiresAt.isAfter(_now.value)) {
        _pairingAttemptId = null;
        _pairingPrompt.value = null;
        unawaited(_auxiliary(_repository.cancelPairing, 'pairingExpiry'));
      }
    });
    try {
      final current = await _repository.initialize();
      if (_closed) return;
      _acceptSnapshot(current);
      _initialization.value = InitializationStatus.ready;
    } catch (error) {
      if (_closed) return;
      _initializationError.value = bridgeFailure(error, 'initialize');
      _initialization.value = InitializationStatus.failed;
    }
  }

  Future<void> retryInitialization() {
    if (_closed || initializationStatus == InitializationStatus.loading) {
      return initialize();
    }
    _initializing = null;
    return initialize();
  }

  void _acceptSnapshot(SessionSnapshot value) {
    if (_closed) return;
    final current = snapshot;
    if (current.runtimeId == value.runtimeId &&
        (value.generation < current.generation ||
            value.sequence < current.sequence)) {
      return;
    }
    _snapshot.value = value;
    final operation = value.operation;
    if ((operation?.kind == OperationKind.pairing &&
            operation?.id == _pairingAttemptId &&
            operation?.state != OperationState.pending) ||
        (current.runtimeId != 'unattached' &&
            current.runtimeId != value.runtimeId)) {
      _pairingPrompt.value = null;
      _pairingAttemptId = null;
    }
  }

  String _operationId() =>
      'op-${DateTime.now().microsecondsSinceEpoch}-${_nextOperation++}';

  Future<void> _command(
    Future<void> Function(String id) action, {
    bool clearing = false,
  }) async {
    if (!_ready) return;
    final intent = ++_intent;
    _auxiliaryErrorStage = null;
    _actionError.value = null;
    _pendingCount.value++;
    if (clearing) _clearing.value = true;
    try {
      await action(_operationId());
    } catch (error) {
      if (!_closed && intent == _intent) {
        _actionError.value = bridgeFailure(error, 'command');
      }
    } finally {
      _pendingCount.value--;
      if (clearing) _clearing.value = false;
    }
  }

  Future<void> connect() async {
    if (canConnect) await _command(_repository.connect);
  }

  Future<void> setLocation(Wgs84Coordinate coordinate) async {
    if (canSet) await _command((id) => _repository.setLocation(id, coordinate));
  }

  Future<void> clearSimulation() async {
    if (canClear) await _command(_repository.clearLocation, clearing: true);
  }

  Future<void> startPairing() async {
    if (_ready && snapshot.capabilities.supportsPairing && !isBusy) {
      await _command((id) async {
        _pairingAttemptId = id;
        try {
          await _repository.startPairing(id);
        } catch (_) {
          if (_pairingAttemptId == id) {
            _pairingAttemptId = null;
            _pairingPrompt.value = null;
          }
          rethrow;
        }
      });
    }
  }

  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  }) async {
    final prompt = pairingPrompt;
    if (!_ready ||
        prompt == null ||
        prompt.id != id ||
        !prompt.expiresAt.isAfter(DateTime.now())) {
      return;
    }
    if (prompt.kind == PairingPromptKind.enterCode &&
        !cancelled &&
        !RegExp(r'^\d{6}$').hasMatch(code ?? '')) {
      _actionError.value = const AppFailure(
        code: 'invalidCode',
        message: '请输入六位数字配对码',
        stage: 'pairing',
        retryable: true,
      );
      _auxiliaryErrorStage = null;
      return;
    }
    if (cancelled) {
      _pairingAttemptId = null;
      _pairingPrompt.value = null;
    }
    await _auxiliary(
      () => _repository.respondToPairing(id, code: code, cancelled: cancelled),
      'pairing',
    );
  }

  Future<void> cancelPairing() async {
    _pairingAttemptId = null;
    _pairingPrompt.value = null;
    await _auxiliary(_repository.cancelPairing, 'pairing');
  }

  Future<void> _auxiliary(Future<void> Function() action, String stage) async {
    if (_closed || _closing.value) return;
    final previousError = _actionError.value;
    try {
      await action();
      if (!_closed &&
          _actionError.value == previousError &&
          _auxiliaryErrorStage == stage) {
        _actionError.value = null;
        _auxiliaryErrorStage = null;
      }
    } catch (error) {
      if (!_closed && !_closing.value) {
        _auxiliaryErrorStage = stage;
        _actionError.value = bridgeFailure(error, stage);
      }
    }
  }

  Future<void> refreshPrerequisites() => _auxiliary(() async {
    final current = await _repository.refresh();
    _acceptSnapshot(current);
  }, 'refresh');

  Future<void> openSetup(SetupTarget target) =>
      _auxiliary(() => _repository.openSetup(target), 'setup');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ready) {
      unawaited(refreshPrerequisites());
    }
  }

  Future<void> shutdown() {
    _closing.value = true;
    _pairingAttemptId = null;
    _pairingPrompt.value = null;
    return _shutdownFuture ??= _shutdown();
  }

  Future<void> _shutdown() async {
    ++_intent;
    try {
      await _repository.shutdown(_operationId());
    } catch (error) {
      _actionError.value = bridgeFailure(error, 'shutdown');
      rethrow;
    } finally {
      _closed = true;
      WidgetsBinding.instance.removeObserver(this);
      _clock?.cancel();
      _pairingPrompt.value = null;
      await _snapshotSubscription?.cancel();
      await _pairingSubscription?.cancel();
      await _repository.dispose();
    }
  }
}
