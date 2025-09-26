// integration_test/complaints_section_test.dart
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

  testWidgets('Scroll to "Your Complaints" and verify section renders', (
    tester,
  ) async {
    app.main();
    await tester.pump();

    await pumpUntilAnyFound(tester, [
      find.textContaining('Good morning'),
      find.text('Sign In'),
    ], const Duration(seconds: 25));

    await signInIfNeeded(tester);

    // Prefer "Profile Address" to avoid GPS churn during tests (if visible).
    final profileToggle = find.text('Profile Address');
    if (profileToggle.evaluate().isNotEmpty) {
      await tester.tap(profileToggle);
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Scroll the FIRST Scrollable on the page until header is visible.
    final header = find.text('Your Complaints');
    final scrollable = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(header, 400, scrollable: scrollable);
    await tester.pump(const Duration(milliseconds: 300)); // settle a bit
    expect(header, findsOneWidget);

    // Wait until either empty-state text or the grid shows up.
    final emptyText = find.text("You haven't made any complaints yet.");
    final grid = find.byType(GridView);

    await pumpUntilAnyFound(tester, [
      emptyText,
      grid,
    ], const Duration(seconds: 30));

    expect(
      emptyText.evaluate().isNotEmpty || grid.evaluate().isNotEmpty,
      isTrue,
      reason: 'Expected either empty-state text or a GridView with cards.',
    );
  });
}
