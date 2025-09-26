// integration_test/complaint_submit_test.dart
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
    'Fill Complains form and submit (no map pick -> shows validation snackbar)',
    (tester) async {
      // 1) Launch app
      app.main();
      await tester.pump();

      // 2) Wait for either greeting or Sign In
      await pumpUntilAnyFound(tester, [
        find.textContaining('Good morning'),
        find.text('Sign In'),
      ], const Duration(seconds: 30));

      // 3) Sign in if needed
      await signInIfNeeded(tester);

      // 4) Go to Complains tab
      await pumpUntilAnyFound(tester, [
        find.text('Complains'),
      ], const Duration(seconds: 20));
      final complaintsTab = find.text('Complains').first;
      await tester.ensureVisible(complaintsTab);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(complaintsTab, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));

      // 5) Ensure form header is visible
      final formHeader = find.text('Complain Form');
      await tester.scrollUntilVisible(
        formHeader,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(formHeader, findsOneWidget);

      // 6) Fill MOH area (Autocomplete field with label)
      final mohField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'MOH Area (Colombo District)',
      );
      expect(mohField, findsOneWidget);
      await tester.ensureVisible(mohField);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(mohField, warnIfMissed: false);
      await tester.enterText(mohField, 'Borella (CMC)');
      await tester.pump(const Duration(milliseconds: 250));

      // 7) Fill Description (hint: 'Description')
      final descField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Description',
      );
      expect(descField, findsOneWidget);
      await tester.ensureVisible(descField);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(descField, warnIfMissed: false);
      await tester.enterText(
        descField,
        'Standing water observed near the park bench; potential mosquito breeding.',
      );
      await tester.pump(const Duration(milliseconds: 250));

      // 8) Fill Location TEXT ONLY (do NOT pick on map or choose a suggestion)
      final locField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Type an address (or tap map icon)',
      );
      expect(locField, findsOneWidget);
      await tester.ensureVisible(locField);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(locField, warnIfMissed: false);
      await tester.enterText(locField, 'Colombo Fort'); // no overlay selection
      await tester.pump(const Duration(milliseconds: 250));

      // 9) (Optional) Toggle Anonymous if present
      final anon = find.byType(Checkbox).first;
      if (anon.evaluate().isNotEmpty) {
        await tester.ensureVisible(anon);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(anon, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 150));
      }

      // 10) Submit (this should show the "Please fill in all fields..." snackbar
      // because _pickedLatLng is still null)
      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit');
      expect(submitBtn, findsOneWidget);
      await tester.ensureVisible(submitBtn);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(submitBtn, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      // 11) Expect the validation snackbar
      const expectedError =
          'Please fill in all fields and pick a valid location (choose a suggestion or use the map).';
      await pumpUntilAnyFound(tester, [
        find.text(expectedError),
        find.byType(SnackBar),
      ], const Duration(seconds: 20));

      expect(
        find.text(expectedError),
        findsOneWidget,
        reason:
            'Expected validation snackbar when lat/lng was not set via map pick or Places suggestion.',
      );
    },
  );
}
