// integration_test/tips_test.dart
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

  testWidgets('Tips carousel is present and scrollable', (tester) async {
    app.main();
    await tester.pump();

    await pumpUntilAnyFound(tester, [
      find.textContaining('Good morning'),
      find.text('Sign In'),
    ], const Duration(seconds: 25));

    await signInIfNeeded(tester);

    // Prefer Profile Address to avoid GPS permission churn in tests
    final profileToggle = find.text('Profile Address');
    if (profileToggle.evaluate().isNotEmpty) {
      await tester.tap(profileToggle);
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Scroll until the tips area (PageView) is visible
    final pageView = find.byType(PageView);
    await tester.scrollUntilVisible(
      pageView,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(pageView, findsOneWidget);

    // Swipe left and right; just ensuring it responds
    await tester.drag(pageView, const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(pageView, const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(pageView, const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 500));

    // Still present after interaction
    expect(pageView, findsOneWidget);
  });
}
