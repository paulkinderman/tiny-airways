import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The game's sound effects, one file each in `assets/sounds/` (made by
/// `tool/build_sounds.py`).
enum Sfx {
  /// The departures board flapping over.
  flap,

  /// A plane leaving the gate.
  takeoff,

  /// A plane landing and its jobs paying out.
  coins,

  /// The airline gaining a level.
  level,

  /// The airline earning a new title.
  promotion,
}

abstract interface class Sounds {
  /// Plays [sfx] once, cutting off the same sound if it is still playing.
  void play(Sfx sfx);
}

/// No sound: the default, and what tests run with.
class SilentSounds implements Sounds {
  const SilentSounds();

  @override
  void play(Sfx sfx) {}
}

/// Plays the effects through audioplayers. Sounds mix with the player's own
/// music and stay quiet when the ringer switch is off.
class AudioSounds implements Sounds {
  AudioSounds._(this._players);

  final Map<Sfx, AudioPlayer> _players;

  /// When false, [play] does nothing (the Settings sound toggle).
  bool enabled = true;

  /// Loads every effect. Never throws: a sound that won't load stays silent.
  static Future<AudioSounds> load() async {
    final players = <Sfx, AudioPlayer>{};
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(respectSilence: true).build(),
      );
      for (final sfx in Sfx.values) {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/${sfx.name}.wav'));
        players[sfx] = player;
      }
    } on Object catch (e) {
      debugPrint('Sounds unavailable: $e');
    }
    return AudioSounds._(players);
  }

  @override
  void play(Sfx sfx) {
    final player = _players[sfx];
    if (!enabled || player == null) return;
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('Sound ${sfx.name} failed: $e');
    });
  }
}

/// The app's sounds. `main()` overrides it with [AudioSounds]; tests keep
/// [SilentSounds].
final soundsProvider = Provider<Sounds>((ref) => const SilentSounds());
