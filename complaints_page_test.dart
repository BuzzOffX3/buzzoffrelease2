import 'package:buzzoff/main.dart' as app;
import 'package:buzzoff/Citizens/complains.dart' show ComplainsPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          as IntegrationTestWidgetsFlutterBinding;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Navigate to Complains page and render', (tester) async {
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
    final complainsTab = find.text('Complains');
    await tester.scrollUntilVisible(complainsTab, 300, scrollable: scrollable);
    await tester.tap(complainsTab);
    await tester.pump(const Duration(milliseconds: 400));

    final byTypeWidget = find.byType(ComplainsPage);
    if (byTypeWidget.evaluate().isNotEmpty) {
      expect(byTypeWidget, findsOneWidget);
    } else {
      expect(
        find.textContaining('Complaint').evaluate().isNotEmpty ||
            find.textContaining('Complaints').evaluate().isNotEmpty,
        isTrue,
      );
    }

    await tester.pump(const Duration(milliseconds: 100));
  }, semanticsEnabled: false);
}
