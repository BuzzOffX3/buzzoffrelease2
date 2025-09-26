import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:buzzoff/main.dart' as app;

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          as IntegrationTestWidgetsFlutterBinding;

  // Run frames live; don't try to fully settle (GoogleMap won't).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Happy path: open app -> sign-in -> land on Maps/Analytics', (
    tester,
  ) async {
    app.main();

    // First frame
    await tester.pump();

    // Wait for either the home greeting OR the login fields to appear.
    await pumpUntilAnyFound(tester, [
      find.textContaining('Good morning'),
      find.byKey(const Key('emailField')),
      find.byKey(const Key('passwordField')),
      find.text('Sign In'),
    ], const Duration(seconds: 20));

    // If already logged in, we're done.
    if (find.textContaining('Good morning').evaluate().isNotEmpty) {
      expect(find.textContaining('Good morning'), findsOneWidget);
      return;
    }

    // Prefer keys (add them in SignInPage if you haven't already).
    Finder email = find.byKey(const Key('emailField'));
    Finder pass = find.byKey(const Key('passwordField'));
    Finder btn = find.byKey(const Key('signInBtn'));

    // Fallbacks if keys don't exist yet:
    if (email.evaluate().isEmpty || pass.evaluate().isEmpty) {
      final tfs = find.byType(TextFormField);
      final tfs2 = find.byType(TextField);
      if (tfs.evaluate().length >= 2) {
        email = tfs.at(0);
        pass = tfs.at(1);
      } else if (tfs2.evaluate().length >= 2) {
        email = tfs2.at(0);
        pass = tfs2.at(1);
      }
    }
    if (btn.evaluate().isEmpty) {
      btn = find.text('Sign In');
    }

    // Enter credentials & tap
    await tester.enterText(email, '789@gmail.com');
    await tester.enterText(pass, '123456789');
    await tester.tap(btn);

    // IMPORTANT: do NOT use pumpAndSettle here (map never settles).
    await pumpUntilFound(
      tester,
      find.textContaining('Good morning'),
      const Duration(seconds: 25),
    );

    expect(find.textContaining('Good morning'), findsOneWidget);
  });
}

/// Pumps the tester periodically until [finder] appears or [timeout] elapses.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder,
  Duration timeout, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('pumpUntilFound timed out waiting for: $finder');
}

/// Pumps until ANY of the [finders] shows up, or throws after [timeout].
Future<void> pumpUntilAnyFound(
  WidgetTester tester,
  List<Finder> finders,
  Duration timeout, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    for (final f in finders) {
      if (f.evaluate().isNotEmpty) return;
    }
  }
  throw TestFailure(
    'pumpUntilAnyFound timed out. None of these appeared: $finders',
  );
}
