import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/ui/split_flap.dart';

void main() {
  group('SplitFlapText.steps', () {
    test('a character that stays put does not flip', () {
      expect(SplitFlapText.steps('A', 'A'), isEmpty);
    });

    test('a character walks the drum to its new letter', () {
      expect(SplitFlapText.steps('A', 'D'), ['B', 'C', 'D']);
    });

    test('a long trip keeps only the last flips', () {
      expect(SplitFlapText.steps('A', 'Z', maxFlips: 3), ['X', 'Y', 'Z']);
    });

    test('the drum wraps around', () {
      expect(SplitFlapText.steps('%', 'A'), [' ', 'A']);
    });

    test('a character off the drum flips straight across', () {
      expect(SplitFlapText.steps('A', 'É'), ['É']);
    });
  });

  Widget board(String text, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Center(
        child: SplitFlapText(text, style: const TextStyle(fontSize: 14)),
      ),
    ),
  );

  testWidgets('a change flips through the drum and settles on the new text', (
    tester,
  ) async {
    await tester.pumpWidget(board('12:00'));
    expect(find.text('12:00'), findsOneWidget);

    await tester.pumpWidget(board('12:05'));
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-flip: the final text is laid out (hidden) and the flaps show the
    // drum one character at a time.
    expect(find.text('12:05'), findsOneWidget);
    expect(find.byType(Transform), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('12:05'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('Reduce Motion changes the text at once', (tester) async {
    await tester.pumpWidget(board('EN ROUTE', reduceMotion: true));
    await tester.pumpWidget(board('HOLDING', reduceMotion: true));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('HOLDING'), findsOneWidget);
  });
}
