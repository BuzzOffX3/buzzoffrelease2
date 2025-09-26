import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits until [finder] appears or throws after [timeout].
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

/// Waits until ANY of [finders] appears or throws after [timeout].
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

/// Signs in if the login screen is visible. Assumes credentials exist.
Future<void> signInIfNeeded(WidgetTester tester) async {
  // Already on home?
  if (find.textContaining('Good morning').evaluate().isNotEmpty) return;

  // Prefer keys if present, else fall back by type/text.
  Finder email = find.byKey(const Key('emailField'));
  Finder pass = find.byKey(const Key('passwordField'));
  Finder btn = find.byKey(const Key('signInBtn'));

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

  await tester.enterText(email, '789@gmail.com');
  await tester.enterText(pass, '123456789');
  await tester.tap(btn);

  await pumpUntilFound(
    tester,
    find.textContaining('Good morning'),
    const Duration(seconds: 25),
  );
}
