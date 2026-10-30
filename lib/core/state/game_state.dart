/// The whole saved state of one airline.
///
/// This is the save schema's root. It starts small (version 1) and grows as
/// packages add systems. Whenever a field is added, removed or renamed in a
/// way old saves don't already match, bump `currentSaveVersion` and add a
/// migration in `lib/core/save/save_migrations.dart`.
class GameState {
  const GameState({
    required this.createdAt,
    required this.lastSeenAt,
    required this.player,
  });

  /// A brand-new airline.
  factory GameState.newGame({
    required DateTime now,
    required int startingMoney,
  }) => GameState(
    createdAt: now,
    lastSeenAt: now,
    player: PlayerState(money: startingMoney, xp: 0, level: 1),
  );

  final DateTime createdAt;

  /// When the game was last running; offline catch-up starts from here.
  final DateTime lastSeenAt;

  final PlayerState player;

  GameState copyWith({DateTime? lastSeenAt, PlayerState? player}) => GameState(
    createdAt: createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    player: player ?? this.player,
  );

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
    'player': player.toJson(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    lastSeenAt: DateTime.parse(json['lastSeenAt'] as String).toUtc(),
    player: PlayerState.fromJson(json['player'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      other is GameState &&
      other.createdAt == createdAt &&
      other.lastSeenAt == lastSeenAt &&
      other.player == player;

  @override
  int get hashCode => Object.hash(createdAt, lastSeenAt, player);
}

/// The airline's money and level.
class PlayerState {
  const PlayerState({
    required this.money,
    required this.xp,
    required this.level,
  });

  /// Coins. Never negative.
  final int money;

  /// Airline XP toward the next level.
  final int xp;

  /// Airline level, starting at 1.
  final int level;

  PlayerState copyWith({int? money, int? xp, int? level}) => PlayerState(
    money: money ?? this.money,
    xp: xp ?? this.xp,
    level: level ?? this.level,
  );

  Map<String, dynamic> toJson() => {'money': money, 'xp': xp, 'level': level};

  factory PlayerState.fromJson(Map<String, dynamic> json) => PlayerState(
    money: json['money'] as int,
    xp: json['xp'] as int,
    level: json['level'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.money == money &&
      other.xp == xp &&
      other.level == level;

  @override
  int get hashCode => Object.hash(money, xp, level);
}
