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

  testWidgets(
    'Sign out returns to Sign In screen',
    (tester) async {
      // Drain/stop at the end to avoid FocusManager-after-dispose.
      addTearDown(() async {
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
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

      // Open the profile menu
      final menuBtn = find.byTooltip('Profile menu');
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap "Sign out"
      final signOutItem = find.text('Sign out');
      expect(signOutItem, findsOneWidget);
      await tester.tap(signOutItem);

      // Wait for sign-in to appear
      await pumpUntilAnyFound(tester, [
        find.text('Sign In'),
        find.text('No account? Register here'),
      ], const Duration(seconds: 20));

      expect(find.text('Sign In'), findsWidgets);

      // One last small pump before exit
      await tester.pump(const Duration(milliseconds: 100));
    },
    semanticsEnabled: false, // helps prevent teardown focus/semantics noise
  );
}
