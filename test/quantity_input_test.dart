import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rigmarket/src/core/app_theme.dart';
import 'package:rigmarket/src/features/payments/checkout_widgets.dart';

void main() {
  testWidgets('quantity supports buttons, typed numbers and enforced bounds', (
    tester,
  ) async {
    final changes = <int>[];
    var valid = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: QuantityInput(
              value: 1,
              onChanged: changes.add,
              onValidityChanged: (value) => valid = value,
            ),
          ),
        ),
      ),
    );
    final minus = find.byKey(const Key('quantity-minus'));
    final plus = find.byKey(const Key('quantity-plus'));
    final input = find.byKey(const Key('quantity-input'));
    expect(tester.widget<IconButton>(minus).onPressed, isNull);
    await tester.tap(plus);
    await tester.pump();
    expect(changes.last, 2);
    await tester.tap(minus);
    await tester.pump();
    expect(changes.last, 1);
    await tester.enterText(input, '20');
    await tester.pump();
    expect(changes.last, 20);
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    await tester.enterText(input, '21');
    await tester.pump();
    expect(valid, isFalse);
    expect(changes.last, 20);
    expect(find.text('Enter a quantity from 1 to 20.'), findsOneWidget);
    await tester.enterText(input, '');
    await tester.pump();
    expect(valid, isFalse);
    await tester.enterText(input, '0');
    await tester.pump();
    expect(valid, isFalse);
    await tester.enterText(input, '7');
    await tester.pump();
    expect(valid, isTrue);
    expect(changes.last, 7);
    expect(tester.takeException(), isNull);
  });
}
