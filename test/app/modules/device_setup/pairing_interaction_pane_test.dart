import 'dart:async';

import 'package:clocation/app/modules/device_setup/widgets/pairing_interaction_pane.dart';
import 'package:clocation/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets(
    'pairing input validates, clears and blocks duplicate submissions',
    (tester) async {
      final completion = Completer<void>();
      final submitted = <String?>[];
      await tester.pumpWidget(
        host(
          PairingInteractionPane(
            title: '输入配对码',
            mode: PairingInteractionMode.enterCode,
            onSubmitted: (code) {
              submitted.add(code);
              return completion.future;
            },
            onCancelled: () async {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), '123');
      await tester.tap(find.text('提交配对码'));
      await tester.pump();
      expect(submitted, isEmpty);
      expect(find.text('请输入六位数字配对码'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('提交配对码'));
      await tester.pump();
      expect(submitted, ['123456']);
      expect(find.widgetWithText(TextFormField, '123456'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('提交配对码'));
      expect(submitted, hasLength(1));

      completion.complete();
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'new interaction discards prior draft and expired prompt cannot submit',
    (tester) async {
      var submissions = 0;
      Widget interaction(String id, {bool expired = false}) => host(
        PairingInteractionPane(
          key: ValueKey(id),
          title: '输入配对码',
          mode: PairingInteractionMode.enterCode,
          isExpired: expired,
          onSubmitted: (_) async => submissions++,
          onCancelled: () async {},
        ),
      );

      await tester.pumpWidget(interaction('first'));
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.pumpWidget(interaction('second', expired: true));
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, isEmpty);
      expect(field.enabled, isFalse);
      await tester.tap(find.text('提交配对码'));
      expect(submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pairing code fits a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PairingInteractionPane(
              title: '输入系统配对界面显示的临时配对码',
              mode: PairingInteractionMode.displayCode,
              displayCode: '123456',
              onSubmitted: (_) async {},
              onCancelled: () async {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('123456'), findsOneWidget);
  });
}
