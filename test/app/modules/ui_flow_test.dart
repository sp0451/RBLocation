import 'dart:async';

import 'package:clocation/app/core/error/app_failure.dart';
import 'package:clocation/app/data/models/geo/wgs84_coordinate.dart';
import 'package:clocation/app/data/models/session/session_snapshot.dart';
import 'package:clocation/app/data/repositories/location_session_repository.dart';
import 'package:clocation/app/routes/app_pages.dart';
import 'package:clocation/app/services/location_session_service.dart';
import 'package:clocation/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  late _UiRepository repository;
  late LocationSessionService service;

  setUp(() async {
    Get.testMode = true;
    repository = _UiRepository();
    service = Get.put(LocationSessionService(repository), permanent: true);
    await service.initialize();
  });

  tearDown(() async {
    repository.finishSet();
    await service.shutdown();
    Get.reset();
    Get.testMode = false;
  });

  Future<void> openWorkspace(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: Routes.LOCATION_WORKSPACE,
        getPages: AppPages.routes,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('startup enters the workspace after managed initialization', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: Routes.STARTUP,
        getPages: AppPages.routes,
        theme: AppTheme.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择位置，开始验证'), findsOneWidget);
    expect(repository.initializeCalls, 1);
  });

  testWidgets(
    'invalid input never submits and choosing a preset only selects',
    (tester) async {
      await openWorkspace(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'NaN');
      await tester.enterText(find.byType(TextFormField).at(1), '121');
      await tapVisible(tester, find.text('设置位置'));
      expect(find.text('请输入有效的纬度数值'), findsOneWidget);
      expect(repository.setCalls, 0);

      await tapVisible(tester, find.widgetWithText(ActionChip, '上海'));
      final fields = tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      );
      expect(fields.first.controller!.text, '31.2304');
      expect(fields.last.controller!.text, '121.4737');
      expect(repository.setCalls, 0);
    },
  );

  testWidgets('stop remains reachable while a set is pending', (tester) async {
    repository.holdSet = true;
    await openWorkspace(tester);
    await tapVisible(tester, find.widgetWithText(ActionChip, '上海'));
    await tapVisible(tester, find.text('设置位置'));
    expect(repository.setCalls, 1);
    expect(service.isBusy, isTrue);
    final stop = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '停止模拟'),
    );
    expect(stop.onPressed, isNotNull);
    await tapVisible(tester, find.text('停止模拟'));
    expect(repository.clearCalls, 1);
    repository.finishSet();
    await tester.pump();
  });

  testWidgets('returning from device setup preserves the application session', (
    tester,
  ) async {
    await openWorkspace(tester);
    await tester.tap(find.byTooltip('设备准备'));
    await tester.pumpAndSettle();
    expect(find.text('先准备，再连接'), findsOneWidget);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('选择位置，开始验证'), findsOneWidget);
    expect(repository.shutdownCalls, 0);
    expect(Get.find<LocationSessionService>(), same(service));
    expect(service.snapshot.connection, SessionConnection.ready);
  });

  testWidgets('pending pairing can be cancelled without replaying a prompt', (
    tester,
  ) async {
    await openWorkspace(tester);
    repository.emitPendingPairing();
    await tester.pump();
    await tester.tap(find.byTooltip('设备准备'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.pairingPrompt, isNull);
    expect(find.text('配对正在进行'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(TextButton, '取消配对'));
    expect(repository.cancelPairingCalls, 1);
  });

  testWidgets('action failures appear without changing the native snapshot', (
    tester,
  ) async {
    repository.setError = const AppFailure(
      code: 'connectionLost',
      message: '测试连接已中断，请重新连接。',
      stage: 'setLocation',
      retryable: true,
    );
    await openWorkspace(tester);
    await tapVisible(tester, find.widgetWithText(ActionChip, '上海'));
    await tapVisible(tester, find.text('设置位置'));
    expect(service.snapshot.failure, isNull);
    expect(find.text('测试连接已中断，请重新连接。'), findsOneWidget);
  });

  testWidgets('workspace supports small screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openWorkspace(tester, textScale: 2);
    await tapVisible(tester, find.widgetWithText(ActionChip, '上海'));
    await tester.ensureVisible(find.text('会话状态'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _UiRepository implements LocationSessionRepository {
  final _snapshots = StreamController<SessionSnapshot>.broadcast();
  final _prompts = StreamController<PairingPrompt>.broadcast();
  final _initial = SessionSnapshot(
    runtimeId: 'ui-test',
    generation: 1,
    sequence: 1,
    connection: SessionConnection.ready,
    recoveryRequired: false,
    capabilities: SessionCapabilities(
      platform: RuntimePlatform.android,
      osVersion: '测试系统',
      engineAvailable: true,
      supportsPairing: false,
      isPaired: false,
      prerequisites: const [],
    ),
  );
  int setCalls = 0;
  int initializeCalls = 0;
  int clearCalls = 0;
  int shutdownCalls = 0;
  int cancelPairingCalls = 0;
  bool holdSet = false;
  AppFailure? setError;
  Completer<void>? _setCompletion;

  @override
  Stream<SessionSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PairingPrompt> get pairingPrompts => _prompts.stream;
  @override
  Future<SessionSnapshot> initialize() async {
    initializeCalls++;
    return _initial;
  }

  @override
  Future<SessionSnapshot> refresh() async => _initial;
  @override
  Future<void> connect(String operationId) async {}
  @override
  Future<void> setLocation(
    String operationId,
    Wgs84Coordinate coordinate,
  ) async {
    setCalls++;
    if (setError != null) throw setError!;
    if (holdSet) await (_setCompletion ??= Completer<void>()).future;
  }

  void finishSet() {
    if (_setCompletion?.isCompleted == false) _setCompletion!.complete();
  }

  void emitPendingPairing() {
    _snapshots.add(
      SessionSnapshot(
        runtimeId: _initial.runtimeId,
        generation: _initial.generation,
        sequence: _initial.sequence + 1,
        connection: SessionConnection.disconnected,
        recoveryRequired: false,
        capabilities: SessionCapabilities(
          platform: RuntimePlatform.ios,
          osVersion: '测试系统',
          engineAvailable: true,
          supportsPairing: true,
          isPaired: false,
          prerequisites: const [],
        ),
        operation: SessionOperation(
          id: 'pair',
          kind: OperationKind.pairing,
          state: OperationState.pending,
          occurredAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Future<void> clearLocation(String operationId) async => clearCalls++;
  @override
  Future<void> startPairing(String operationId) async {}
  @override
  Future<void> respondToPairing(
    String id, {
    String? code,
    bool cancelled = false,
  }) async {}
  @override
  Future<void> cancelPairing() async => cancelPairingCalls++;
  @override
  Future<void> openSetup(SetupTarget target) async {}
  @override
  Future<void> shutdown(String operationId) async => shutdownCalls++;
  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _prompts.close();
  }
}
