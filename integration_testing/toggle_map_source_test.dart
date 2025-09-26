import 'package:buzzoff/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          as IntegrationTestWidgetsFlutterBinding;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Toggle map source and re-center without errors', (tester) async {
    // Drain/stop at the end to avoid FocusManager-after-dispose.
    addTearDown(() async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    });

    app.main();
    await tester.pump();

    await pumpUntilAnyFound(tester, [
      find.textContaining('Good morning'),
      find.text('Sign In'),
    ], const Duration(seconds: 25));

    await signInIfNeeded(tester);

    // Prefer Profile Address to avoid GPS churn (if available)
    final profile = find.text('Profile Address');
    if (profile.evaluate().isNotEmpty) {
      await tester.tap(profile);
      await tester.pump(const Duration(milliseconds: 700));
    }

    // Ensure map controls are on-screen
    final scrollable = find.byType(Scrollable).first;
    final recenterBtn = find.byIcon(Icons.my_location);
    await tester.scrollUntilVisible(recenterBtn, 500, scrollable: scrollable);
    await tester.pump(const Duration(milliseconds: 300));

    // Toggle back to Current Location if present
    final current = find.text('Current Location');
    if (current.evaluate().isNotEmpty) {
      await tester.tap(current);
      await tester.pump(const Duration(milliseconds: 700));
    }

    // Tap re-center to ensure map still responds
    if (recenterBtn.evaluate().isNotEmpty) {
      await tester.tap(recenterBtn);
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(
      find.textContaining('SEE DENGUE PATIENTS CLOSE TO YOU'),
      findsWidgets,
    );

    // Small extra pump before exit
    await tester.pump(const Duration(milliseconds: 100));
  }, semanticsEnabled: false);
}
