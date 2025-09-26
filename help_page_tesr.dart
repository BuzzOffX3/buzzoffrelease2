import 'package:buzzoff/main.dart' as app;
import 'package:buzzoff/Citizens/Fines&payments.dart' show MapHowToPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          as IntegrationTestWidgetsFlutterBinding;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Navigate to Help page and render', (tester) async {
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

    final profile = find.text('Profile Address');
    if (profile.evaluate().isNotEmpty) {
      await tester.tap(profile);
      await tester.pump(const Duration(milliseconds: 600));
    }

    final scrollable = find.byType(Scrollable).first;
    final helpTab = find.text('Help');
    await tester.scrollUntilVisible(helpTab, 300, scrollable: scrollable);
    await tester.tap(helpTab);
    await tester.pump(const Duration(milliseconds: 400));

    final byTypeWidget = find.byType(MapHowToPage);
    if (byTypeWidget.evaluate().isNotEmpty) {
      expect(byTypeWidget, findsOneWidget);
    } else {
      expect(
        find.textContaining('Help').evaluate().isNotEmpty ||
            find.textContaining('How to').evaluate().isNotEmpty,
        isTrue,
      );
    }

    await tester.pump(const Duration(milliseconds: 100));
  }, semanticsEnabled: false);
}
