import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tiny_airways/main.dart' as app;

/// Launches the real app (real asset bundle, real save folder) on a device or
/// simulator. CI runs this on an iOS simulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app launches to the continent picker or the map', (
    tester,
  ) async {
    await app.main();
    // The Flame game loop never settles, so pump for a fixed time instead of
    // pumpAndSettle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // A fresh install asks for a home; a returning airline opens the map.
    final picker = find.text('CHOOSE YOUR HOME');
    final topBar = find.byKey(const Key('topBar.money'));
    expect(
      picker.evaluate().isNotEmpty || topBar.evaluate().isNotEmpty,
      isTrue,
    );
  });
}
