import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rigmarket/src/app.dart';

void main() {
  testWidgets(
    'preview browsing, categories and protected actions work on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: RigMarketApp()));
      await tester.pumpAndSettle();
      expect(find.text('Your next build\nstarts here.'), findsOneWidget);
      expect(find.textContaining('Sample listings'), findsOneWidget);
      await tester.tap(find.text('Categories').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CPUs'));
      await tester.pumpAndSettle();
      expect(find.text('CPUs'), findsOneWidget);
      await tester.tap(find.text('Cart').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in or create account'));
      await tester.pumpAndSettle();
      expect(find.text('Connect your marketplace'), findsOneWidget);
      await tester.tap(find.text('View connection instructions'));
      await tester.pumpAndSettle();
      expect(find.text('From preview to your marketplace.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('home supports enlarged text without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const ProviderScope(child: RigMarketApp()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
