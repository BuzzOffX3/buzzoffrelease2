import 'package:flutter/material.dart'; // <-- needed for TextField
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart'; // <-- provides patrolTest and the $ API
// If you specifically want standalone finders, you can also keep:
// import 'package:patrol_finders/patrol_finders.dart';

import 'package:buzzoff/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolTest('Login flow shows username on Analytics header', ($) async {
    app.main();
    await $.pumpAndSettle();

    // Adjust these finders to match your actual login fields/buttons
    await $(TextField).at(0).enterText('789@gmail.com');
    await $(TextField).at(1).enterText('123456789');
    await $('Sign In').tap();

    await $.pumpAndSettle();

    // Example assertion — change the text to what your app really shows
    await $('Good morning').waitUntilVisible();
  });
}
