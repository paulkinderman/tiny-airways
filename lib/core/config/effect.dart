import 'config_reader.dart';

/// One bonus from an upgrade tier, skill node or terminal node, such as
/// `{"effect": "passengerPayPct", "value": 15}`.
///
/// [effect] is a stable key the rules switch on; [value] is its size (a
/// percentage for `...Pct` keys, a count or multiplier otherwise); [text] is
/// what the player reads.
class Effect {
  const Effect({required this.effect, required this.value, required this.text});

  factory Effect.fromConfig(ConfigReader c) => Effect(
    effect: c.string('effect'),
    value: c.number('value'),
    text: c.string('text'),
  );

  final String effect;
  final double value;
  final String text;
}
