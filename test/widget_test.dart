import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silong_hamuros/main.dart';
import 'package:silong_hamuros/controller.dart';

void main() {
  testWidgets(
      'live app has honest empty states, brown-green theme and no simulator',
      (tester) async {
    final c = DryingController(polling: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(SilongApp(controller: c));
    expect(find.text('SILONG HAMUROS'), findsOneWidget);
    expect(find.text('DEMO'), findsNothing);
    expect(find.text('Cover status unavailable'), findsOneWidget);
    final context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).colorScheme.primary, brown);
    expect(Theme.of(context).colorScheme.secondary, green);
    await tester.tap(find.text('Batches'));
    await tester.pumpAndSettle();
    expect(find.text('No batches recorded yet.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Configure connection'), findsOneWidget);
    expect(find.text('Demo device simulator'), findsNothing);
    expect(find.text('Send sample reading'), findsNothing);
    await tester.tap(find.text('Configure connection'));
    await tester.pumpAndSettle();
    expect(find.text('Server URL'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
