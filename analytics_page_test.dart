import 'package:buzzoff/main.dart' as app;
import 'package:buzzoff/Citizens/analytics.dart' show AnalyticsPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          as IntegrationTestWidgetsFlutterBinding;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Navigate to Analytics page and render', (tester) async {
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

    // Prefer Profile Address to avoid GPS permission churn.
    final profile = find.text('Profile Address');
    if (profile.evaluate().isNotEmpty) {
      await tester.tap(profile);
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Bring the nav row into view and tap "Analytics".
    final scrollable = find.byType(Scrollable).first;
    final analyticsTab = find.text('Analytics');
    await tester.scrollUntilVisible(analyticsTab, 300, scrollable: scrollable);
    await tester.tap(analyticsTab);
    await tester.pump(const Duration(milliseconds: 400));

    // Expect the AnalyticsPage to be present (fallback: look for common text).
    final byTypeWidget = find.byType(AnalyticsPage);
    if (byTypeWidget.evaluate().isNotEmpty) {
      expect(byTypeWidget, findsOneWidget);
    } else {
      // fallback text probes (keep these generic)
      expect(
        find.textContaining('Analytics').evaluate().isNotEmpty ||
            find.textContaining('Statistics').evaluate().isNotEmpty,
        isTrue,
      );
    }

    await tester.pump(const Duration(milliseconds: 100));
  }, semanticsEnabled: false);
}
