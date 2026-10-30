import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/ui/plane_art.dart';

void main() {
  test('every plane model has art', () async {
    final config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    final planes = config.planes;
    for (final model in [...planes.models, ...planes.specialModels]) {
      final file = File(PlaneArt.assetFor(model.id));
      expect(file.existsSync(), isTrue, reason: '${model.id} has no art');
      expect(file.readAsStringSync(), contains('viewBox="0 0 260 130"'));
    }
  });

  testWidgets('a model without art falls back to an icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: PlaneArt('no_such_plane'))),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flight), findsOneWidget);
    expect(tester.getSize(find.byType(PlaneArt)), const Size(96, 48));
  });
}
