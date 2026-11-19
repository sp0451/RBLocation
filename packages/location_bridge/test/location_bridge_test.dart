import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_bridge/location_bridge.dart';
import 'package:location_bridge/src/generated/location_api.g.dart' as wire;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LocationBridge bridge;
  BasicMessageChannel<Object?> hostChannel(String name) =>
      BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.location_bridge.NativeLocationApi.$name',
        wire.NativeLocationApi.pigeonChannelCodec,
      );
  Future<void> event(String name, Object argument) {
    final reply = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      'dev.flutter.pigeon.location_bridge.NativeLocationEvents.$name',
      wire.NativeLocationEvents.pigeonChannelCodec.encodeMessage([argument]),
      (_) => reply.complete(),
    );
    return reply.future;
  }

  setUp(() {
    messenger.setMockDecodedMessageHandler<Object?>(
      hostChannel('detach'),
      (_) async => <Object?>[null],
    );
    bridge = LocationBridge();
  });
  tearDown(() async {
    await bridge.dispose();
    for (final method in ['attach', 'setLocation', 'detach']) {
      messenger.setMockDecodedMessageHandler<Object?>(
        hostChannel(method),
        null,
      );
    }
  });

  test(
    'decodes snapshot and does not invent a sample from the command target',
    () async {
      final snapshot = wire.WireSnapshot(
        runtimeId: 'runtime',
        generation: 2,
        sequence: 7,
        connection: wire.WireConnection.ready,
        recoveryRequired: true,
        capabilities: wire.WireCapabilities(
          platform: wire.WirePlatform.ios,
          osVersion: '27.0.1',
          engineAvailable: true,
          supportsPairing: true,
          isPaired: true,
          prerequisites: [],
        ),
        operation: wire.WireOperation(
          id: 'set',
          kind: wire.WireOperationKind.setLocation,
          state: wire.WireCommandState.sent,
          occurredAtMillis: 1000,
          coordinate: wire.WireCoordinate(latitude: 31, longitude: 121),
        ),
      );
      messenger.setMockDecodedMessageHandler<Object?>(
        hostChannel('attach'),
        (_) async => <Object?>[snapshot],
      );
      final result = await bridge.attach();
      expect(result.runtimeId, 'runtime');
      expect(result.operation?.state, CommandPhase.sent);
      expect(result.operation?.coordinate?.longitude, 121);
      expect(result.sample, isNull);
      final updates = <NativeSnapshot>[];
      final subscription = bridge.snapshots.listen(updates.add);
      await event('onSnapshot', snapshot);
      expect(updates.single.sequence, 7);
      await subscription.cancel();
    },
  );

  test(
    'pairing event carries attempt id and is not replayed to later listeners',
    () async {
      final prompts = <NativePairingInteraction>[];
      final subscription = bridge.pairingInteractions.listen(prompts.add);
      await event(
        'onPairingInteraction',
        wire.WirePairingInteraction(
          id: 'interaction',
          operationId: 'pair-attempt',
          kind: wire.WirePairingKind.displayCode,
          title: '配对',
          expiresAtMillis: 1000,
          displayCode: '123456',
        ),
      );
      expect(prompts.single.operationId, 'pair-attempt');
      await subscription.cancel();
      final later = <NativePairingInteraction>[];
      final laterSubscription = bridge.pairingInteractions.listen(later.add);
      await Future<void>.delayed(Duration.zero);
      expect(later, isEmpty);
      await laterSubscription.cancel();
    },
  );

  test(
    'native errors retain code and disposed facade refuses commands',
    () async {
      messenger.setMockDecodedMessageHandler<Object?>(
        hostChannel('attach'),
        (_) async => <Object?>['permissionDenied', '请授予权限', null],
      );
      await expectLater(
        bridge.attach(),
        throwsA(
          isA<NativeBridgeException>().having(
            (e) => e.code,
            'code',
            'permissionDenied',
          ),
        ),
      );
      await bridge.dispose();
      await expectLater(
        bridge.attach(),
        throwsA(
          isA<NativeBridgeException>().having(
            (e) => e.code,
            'code',
            'disposed',
          ),
        ),
      );
    },
  );
}
